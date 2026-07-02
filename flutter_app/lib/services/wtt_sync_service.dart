import 'dart:convert';

import 'package:http/http.dart' as http;
import 'package:supabase_flutter/supabase_flutter.dart';

import '../config/supabase_config.dart';

class WttSyncResult {
  const WttSyncResult({
    required this.athletesSynced,
    required this.rankingWeek,
    required this.rankingYear,
    required this.hasUpdates,
  });

  final int athletesSynced;
  final String? rankingWeek;
  final String? rankingYear;
  final bool hasUpdates;
}

class WttSyncService {
  WttSyncService({SupabaseClient? client, http.Client? httpClient})
      : _client = client ?? SupabaseConfig.client,
        _http = httpClient ?? http.Client();

  final SupabaseClient _client;
  final http.Client _http;

  static const _headers = {
    'Accept': 'application/json, text/plain, */*',
    'Referer': 'https://www.worldtabletennis.com/',
    'Origin': 'https://www.worldtabletennis.com',
    'User-Agent':
        'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36',
    'ApiKey': '2bf8b222-532c-4c60-8ebe-eb6fdfebe84a',
  };

  static const _rankingUrl =
      'https://wtt-web-frontdoor-withoutcache-cqakg0andqf5hchn.a01.azurefd.net/ranking/SEN_SINGLES.json';
  static const _playersUrl =
      'https://wtt-ttu-connect-frontdoor-g6gwg6e2bgc6gdfm.a01.azurefd.net/Players/GetPlayers';
  static const _playerCardUrl =
      'https://wtt-website-api-prod-3-frontdoor-bddnb2haduafdze9.a01.azurefd.net/api/cms/PlayerCard/';

  Future<WttSyncResult> syncFromWtt({
    void Function(String message, double progress)? onProgress,
  }) async {
    onProgress?.call('Consultando rankings na WTT...', 0.05);

    final rankingResponse = await _http.get(
      Uri.parse('$_rankingUrl?q=${DateTime.now().millisecondsSinceEpoch}'),
      headers: _headers,
    );

    if (rankingResponse.statusCode != 200) {
      throw Exception('Falha ao buscar rankings WTT (${rankingResponse.statusCode})');
    }

    final payload = jsonDecode(rankingResponse.body) as Map<String, dynamic>;
    final allRankings = (payload['Result'] as List?) ?? [];

    final remoteMeta = _extractRankingMeta(allRankings);
    final localMeta = await _fetchLocalRankingMeta();
    final hasUpdates = _hasNewRankingData(localMeta, remoteMeta);

    if (!hasUpdates && localMeta != null) {
      onProgress?.call('Dados já estão atualizados.', 1);
      return WttSyncResult(
        athletesSynced: 0,
        rankingWeek: remoteMeta?.week,
        rankingYear: remoteMeta?.year,
        hasUpdates: false,
      );
    }

    final targets = ['MS', 'WS'];
    final athletes = <Map<String, dynamic>>[];
    var processed = 0;
    const totalSteps = 200;

    for (final subEvent in targets) {
      final rows = _collectGenderRankings(allRankings, subEvent);
      for (final row in rows) {
        processed++;
        onProgress?.call(
          'Sincronizando ${row['PlayerName']}...',
          processed / totalSteps,
        );

        final ittfId = row['IttfId']?.toString() ?? '';
        Map<String, dynamic> profile = {};
        Map<String, dynamic> card = {};

        if (ittfId.isNotEmpty) {
          profile = await _fetchPlayerProfile(ittfId);
          card = await _fetchPlayerCard(ittfId);
          await Future<void>.delayed(const Duration(milliseconds: 120));
        }

        athletes.add(_buildAthleteRecord(row, profile, card));
      }
    }

    onProgress?.call('Salvando no Supabase...', 0.95);
    await _client.from('athletes').upsert(
      athletes,
      onConflict: 'name,gender',
    );

    onProgress?.call('Atualização concluída!', 1);

    return WttSyncResult(
      athletesSynced: athletes.length,
      rankingWeek: remoteMeta?.week,
      rankingYear: remoteMeta?.year,
      hasUpdates: true,
    );
  }

  Future<_RankingMeta?> _fetchLocalRankingMeta() async {
    final row = await _client
        .from('athletes')
        .select('updated_at')
        .order('updated_at', ascending: false)
        .limit(1)
        .maybeSingle();

    if (row == null) {
      return null;
    }

    final updatedAt = DateTime.tryParse(row['updated_at']?.toString() ?? '');
    return _RankingMeta(week: null, year: null, latestUpdate: updatedAt);
  }

  bool _hasNewRankingData(_RankingMeta? local, _RankingMeta? remote) {
    if (local == null || remote == null) {
      return true;
    }

    if (remote.week != null &&
        remote.year != null &&
        (local.week != remote.week || local.year != remote.year)) {
      return true;
    }

    if (local.latestUpdate == null) {
      return true;
    }

    return DateTime.now().difference(local.latestUpdate!).inDays >= 7;
  }

  _RankingMeta? _extractRankingMeta(List<dynamic> rankings) {
    if (rankings.isEmpty) {
      return null;
    }

    final first = rankings.first as Map<String, dynamic>;
    return _RankingMeta(
      week: first['RankingWeek']?.toString(),
      year: first['RankingYear']?.toString(),
      latestUpdate: null,
    );
  }

  List<Map<String, dynamic>> _collectGenderRankings(
    List<dynamic> allRankings,
    String subEventCode, {
    int limit = 100,
  }) {
    final filtered = allRankings
        .whereType<Map<String, dynamic>>()
        .where((row) => row['SubEventCode'] == subEventCode)
        .toList()
      ..sort(
        (a, b) => (_parseInt(a['CurrentRank']) ?? 9999)
            .compareTo(_parseInt(b['CurrentRank']) ?? 9999),
      );

    return filtered.take(limit).toList();
  }

  Future<Map<String, dynamic>> _fetchPlayerProfile(String ittfId) async {
    final uri = Uri.parse(_playersUrl).replace(
      queryParameters: {
        'IttfId': ittfId,
        'q': '${DateTime.now().millisecondsSinceEpoch}',
      },
    );

    final response = await _http.get(uri, headers: _headers);
    if (response.statusCode != 200) {
      return {};
    }

    final payload = jsonDecode(response.body) as Map<String, dynamic>;
    final result = (payload['Result'] as List?) ?? [];
    if (result.isEmpty) {
      return {};
    }

    return Map<String, dynamic>.from(result.first as Map);
  }

  Future<Map<String, dynamic>> _fetchPlayerCard(String ittfId) async {
    final response = await _http.get(
      Uri.parse('$_playerCardUrl$ittfId'),
      headers: _headers,
    );

    if (response.statusCode != 200) {
      return {};
    }

    final payload = jsonDecode(response.body) as Map<String, dynamic>;
    final detailsRaw = payload['details'];
    if (detailsRaw == null) {
      return {};
    }

    try {
      return Map<String, dynamic>.from(
        jsonDecode(detailsRaw as String) as Map,
      );
    } catch (_) {
      return {};
    }
  }

  Map<String, dynamic> _buildAthleteRecord(
    Map<String, dynamic> rankingRow,
    Map<String, dynamic> profile,
    Map<String, dynamic> card,
  ) {
    final subEvent = rankingRow['SubEventCode']?.toString() ?? '';
    final gender = subEvent == 'MS'
        ? 'male'
        : subEvent == 'WS'
            ? 'female'
            : null;

    if (gender == null) {
      throw StateError('SubEventCode desconhecido: $subEvent');
    }

    final photo = profile['HeadshotR'] ??
        profile['HeadShot'] ??
        profile['HeadshotL'];

    return {
      'name': rankingRow['PlayerName'] ?? profile['PlayerName'],
      'gender': gender,
      'ranking': _parseInt(
        rankingRow['CurrentRank'] ?? rankingRow['RankingPosition'],
      ),
      'ranking_points': _parseInt(
        rankingRow['RankingPointsYTD'] ?? rankingRow['RankingPointsCareer'],
      ),
      'age': _parseInt(profile['Age'] ?? rankingRow['Age']),
      'height': _parseDouble(card['Height'] ?? profile['Height']),
      'hand': profile['Handedness'] ?? card['Hand'],
      'championships_won': _buildChampionships(card),
      'photo_url': _normalizePhotoUrl(photo?.toString()),
      'updated_at': DateTime.now().toUtc().toIso8601String(),
    };
  }

  List<String> _buildChampionships(Map<String, dynamic> card) {
    final titles = <String>[];

    final singles = card['singles_titles'];
    final doubles = card['doubles_titles'];
    if (singles != null && '$singles'.isNotEmpty) {
      titles.add(_translateHighlight('Singles titles: $singles'));
    }
    if (doubles != null && '$doubles'.isNotEmpty) {
      titles.add(_translateHighlight('Doubles titles: $doubles'));
    }

    final statsRaw = card['stats'];
    if (statsRaw != null) {
      try {
        final stats = statsRaw is String
            ? jsonDecode(statsRaw) as Map<String, dynamic>
            : Map<String, dynamic>.from(statsRaw as Map);
        final careerTitles =
            stats['career_titles'] ?? stats['tournament_wins'];
        if (careerTitles != null) {
          titles.add(_translateHighlight('Career titles: $careerTitles'));
        }
      } catch (_) {}
    }

    final highlightsRaw = card['highlights'];
    if (highlightsRaw != null) {
      try {
        final highlights = highlightsRaw is String
            ? jsonDecode(highlightsRaw) as List<dynamic>
            : highlightsRaw as List<dynamic>;
        for (final item in highlights) {
          final map = Map<String, dynamic>.from(item as Map);
          final year = map['year'];
          for (final key in ['singles', 'doubles', 'mixed']) {
            final value = map[key];
            if (value != null && '$value'.isNotEmpty) {
              titles.add(_translateHighlight('$year $key: $value'));
            }
          }
        }
      } catch (_) {}
    }

    if (card['result'] != null && card['event_name'] != null) {
      titles.add('${card['event_name']}: ${card['result']}');
    }

    return titles.take(20).toList();
  }

  String _translateHighlight(String text) {
    const replacements = {
      'Singles titles:': 'Títulos em simples:',
      'Doubles titles:': 'Títulos em duplas:',
      'Career titles:': 'Títulos na carreira:',
      ' singles:': ' simples:',
      ' doubles:': ' duplas:',
      ' mixed:': ' mista:',
    };

    var translated = text;
    for (final entry in replacements.entries) {
      translated = translated.replaceAll(entry.key, entry.value);
    }
    return translated;
  }

  String? _normalizePhotoUrl(String? url) {
    if (url == null || url.isEmpty || url.toLowerCase().contains('dummy')) {
      return null;
    }

    return url
        .replaceAll(
          'https://wttsimfiles.blob.core.windows.net',
          'https://photofiles.worldtabletennis.com',
        )
        .replaceAll(
          'https://wttnewtest.blob.core.windows.net',
          'https://photofiles.worldtabletennis.com',
        );
  }

  int? _parseInt(Object? value) {
    if (value == null || '$value'.isEmpty) {
      return null;
    }
    return int.tryParse('${double.tryParse('$value')}');
  }

  double? _parseDouble(Object? value) {
    if (value == null || '$value'.isEmpty) {
      return null;
    }
    return double.tryParse('$value');
  }
}

class _RankingMeta {
  const _RankingMeta({
    required this.week,
    required this.year,
    required this.latestUpdate,
  });

  final String? week;
  final String? year;
  final DateTime? latestUpdate;
}
