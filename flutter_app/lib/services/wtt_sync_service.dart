import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import 'package:supabase_flutter/supabase_flutter.dart';

import '../config/supabase_config.dart';
import '../utils/title_utils.dart';

class WttSyncResult {
  const WttSyncResult({
    required this.athletesSynced,
    required this.rankingWeek,
    required this.rankingYear,
    required this.hasUpdates,
    required this.athletesChanged,
  });

  final int athletesSynced;
  final String? rankingWeek;
  final String? rankingYear;
  final bool hasUpdates;
  final int athletesChanged;
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

  static const _wikiHeaders = {
    'User-Agent': 'TM-Val/1.0 (tm-val-app)',
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
    if (kIsWeb) {
      return _syncViaEdgeFunction(onProgress);
    }

    onProgress?.call('Consultando rankings na WTT...', 0.05);

    final existingRows = await _fetchExistingAthletes();
    final existingByKey = {
      for (final row in existingRows)
        _athleteKey(row['name']?.toString() ?? '', row['gender']?.toString() ?? ''):
            row,
    };

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

    final targets = ['MS', 'WS'];
    final athletes = <Map<String, dynamic>>[];
    var processed = 0;
    const totalSteps = 200;
    var changedCount = 0;

    for (final subEvent in targets) {
      final rows = _collectGenderRankings(allRankings, subEvent);
      for (final row in rows) {
        processed++;
        final playerName = row['PlayerName']?.toString() ?? 'Atleta';
        onProgress?.call(
          'Sincronizando $playerName...',
          processed / totalSteps,
        );

        final ittfId = row['IttfId']?.toString() ?? '';
        Map<String, dynamic> profile = {};
        Map<String, dynamic> card = {};

        if (ittfId.isNotEmpty) {
          profile = await _fetchPlayerProfile(ittfId);
          card = await _fetchPlayerCard(ittfId);
          await Future<void>.delayed(const Duration(milliseconds: 100));
        }

        final record = await _buildAthleteRecord(row, profile, card);
        final key = _athleteKey(
          record['name']?.toString() ?? '',
          record['gender']?.toString() ?? '',
        );
        if (_recordChanged(existingByKey[key], record)) {
          changedCount++;
        }
        athletes.add(record);
      }
    }

    onProgress?.call('Salvando no Supabase...', 0.95);
    await _client.from('athletes').upsert(
      athletes,
      onConflict: 'name,gender',
    );

    onProgress?.call('Atualização concluída!', 1);

    final rankingChanged = _detectRankingWeekChange(existingRows, remoteMeta);

    return WttSyncResult(
      athletesSynced: athletes.length,
      rankingWeek: remoteMeta?.week,
      rankingYear: remoteMeta?.year,
      hasUpdates: changedCount > 0 || rankingChanged,
      athletesChanged: changedCount,
    );
  }

  Future<WttSyncResult> _syncViaEdgeFunction(
    void Function(String message, double progress)? onProgress,
  ) async {
    onProgress?.call(
      'Sincronizando 200 atletas via servidor (evita bloqueio CORS)...',
      0.1,
    );

    final response = await _client.functions.invoke(
      'sync-wtt',
      body: const {},
    );

    if (response.status != 200) {
      final details = response.data?.toString() ?? 'sem detalhes';
      throw Exception('Falha na sincronização ($details)');
    }

    final data = Map<String, dynamic>.from(response.data as Map);
    if (data['error'] != null) {
      throw Exception(data['error'].toString());
    }

    onProgress?.call('Atualização concluída!', 1);

    return WttSyncResult(
      athletesSynced: _parseInt(data['athletesSynced']) ?? 0,
      rankingWeek: data['rankingWeek']?.toString(),
      rankingYear: data['rankingYear']?.toString(),
      hasUpdates: data['hasUpdates'] == true,
      athletesChanged: _parseInt(data['athletesChanged']) ?? 0,
    );
  }

  String _athleteKey(String name, String gender) => '$name|$gender';

  Future<List<Map<String, dynamic>>> _fetchExistingAthletes() async {
    final rows = await _client.from('athletes').select(
      'name,gender,ranking,ranking_points,age,height,hand,championships_won,ittf_id,photo_url',
    );
    return (rows as List)
        .map((row) => Map<String, dynamic>.from(row as Map))
        .toList();
  }

  bool _detectRankingWeekChange(
    List<Map<String, dynamic>> existing,
    _RankingMeta? remote,
  ) {
    if (existing.isEmpty || remote?.week == null) {
      return existing.isEmpty;
    }
    return false;
  }

  bool _recordChanged(
    Map<String, dynamic>? existing,
    Map<String, dynamic> record,
  ) {
    if (existing == null) {
      return true;
    }

    bool listEq(Object? a, Object? b) {
      final la = (a as List?)?.map((e) => e.toString()).toList() ?? [];
      final lb = (b as List?)?.map((e) => e.toString()).toList() ?? [];
      if (la.length != lb.length) {
        return false;
      }
      for (var i = 0; i < la.length; i++) {
        if (la[i] != lb[i]) {
          return false;
        }
      }
      return true;
    }

    return existing['ranking'] != record['ranking'] ||
        existing['ranking_points'] != record['ranking_points'] ||
        existing['age'] != record['age'] ||
        existing['height']?.toString() != record['height']?.toString() ||
        existing['hand']?.toString() != record['hand']?.toString() ||
        existing['ittf_id']?.toString() != record['ittf_id']?.toString() ||
        existing['photo_url']?.toString() != record['photo_url']?.toString() ||
        !listEq(existing['championships_won'], record['championships_won']);
  }

  _RankingMeta? _extractRankingMeta(List<dynamic> rankings) {
    if (rankings.isEmpty) {
      return null;
    }

    final first = rankings.first as Map<String, dynamic>;
    return _RankingMeta(
      week: first['RankingWeek']?.toString(),
      year: first['RankingYear']?.toString(),
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

  Future<Map<String, dynamic>> _buildAthleteRecord(
    Map<String, dynamic> rankingRow,
    Map<String, dynamic> profile,
    Map<String, dynamic> card,
  ) async {
    final subEvent = rankingRow['SubEventCode']?.toString() ?? '';
    final gender = subEvent == 'MS'
        ? 'male'
        : subEvent == 'WS'
            ? 'female'
            : null;

    if (gender == null) {
      throw StateError('SubEventCode desconhecido: $subEvent');
    }

    final name = rankingRow['PlayerName'] ?? profile['PlayerName'];
    final ittfId = rankingRow['IttfId']?.toString() ?? '';
    final photo = profile['HeadshotR'] ??
        profile['HeadShot'] ??
        profile['HeadshotL'];

    final cardTitles = _buildChampionshipsFromCard(card);
    final wikiTitles = _needsWikiEnrichment(cardTitles)
        ? await _fetchWikipediaTitles(name?.toString() ?? '')
        : <String>[];

    return {
      'name': name,
      'gender': gender,
      'ittf_id': ittfId.isEmpty ? null : ittfId,
      'ranking': _parseInt(
        rankingRow['CurrentRank'] ?? rankingRow['RankingPosition'],
      ),
      'ranking_points': _parseInt(
        rankingRow['RankingPointsYTD'] ?? rankingRow['RankingPointsCareer'],
      ),
      'age': _parseInt(profile['Age'] ?? rankingRow['Age']),
      'height': _parseDouble(card['Height'] ?? profile['Height']),
      'hand': profile['Handedness'] ?? card['Hand'],
      'championships_won': TitleUtils.mergeUnique(cardTitles, wikiTitles),
      'photo_url': _normalizePhotoUrl(photo?.toString()),
      'updated_at': DateTime.now().toUtc().toIso8601String(),
    };
  }

  List<String> _buildChampionshipsFromCard(Map<String, dynamic> card) {
    final titles = <String>[];

    final singles = card['singles_titles'];
    final doubles = card['doubles_titles'];
    if (singles != null && '$singles'.isNotEmpty) {
      titles.add('Singles titles: $singles');
    }
    if (doubles != null && '$doubles'.isNotEmpty) {
      titles.add('Doubles titles: $doubles');
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
          titles.add('Career titles: $careerTitles');
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
            if (value == null || '$value'.isEmpty) {
              continue;
            }
            for (final tournament in TitleUtils.splitTournamentList('$value')) {
              titles.add('$year $key: $tournament');
            }
          }
        }
      } catch (_) {}
    }

    if (card['result'] != null && card['event_name'] != null) {
      titles.add('${card['event_name']}: ${card['result']}');
    }

    if (card['last_result'] != null) {
      titles.add('Último resultado: ${card['last_result']}');
    }

    return titles;
  }

  bool _needsWikiEnrichment(List<String> cardTitles) {
    return !cardTitles.any((title) {
      final year = TitleUtils.extractYear(title);
      return year != null && year >= 2022;
    });
  }

  Future<List<String>> _fetchWikipediaTitles(String playerName) async {
    if (playerName.trim().isEmpty) {
      return [];
    }

    try {
      final searchUri = Uri.https('en.wikipedia.org', '/w/api.php', {
        'action': 'query',
        'list': 'search',
        'srsearch': '$playerName table tennis',
        'srlimit': '2',
        'format': 'json',
      });
      final searchResp =
          await _http.get(searchUri, headers: _wikiHeaders).timeout(
                const Duration(seconds: 10),
              );
      if (searchResp.statusCode != 200) {
        return [];
      }

      final hits = (jsonDecode(searchResp.body) as Map)['query']?['search']
          as List?;
      if (hits == null || hits.isEmpty) {
        return [];
      }

      final page = hits.first['title'] as String;
      final parseUri = Uri.https('en.wikipedia.org', '/w/api.php', {
        'action': 'parse',
        'page': page,
        'prop': 'wikitext',
        'format': 'json',
      });
      final parseResp =
          await _http.get(parseUri, headers: _wikiHeaders).timeout(
                const Duration(seconds: 10),
              );
      if (parseResp.statusCode != 200) {
        return [];
      }

      final wikitext = (jsonDecode(parseResp.body) as Map)['parse']?['wikitext']
          ?['*'] as String?;
      if (wikitext == null) {
        return [];
      }

      final titles = <String>[];
      final medalBlocks = RegExp(
        r'\{\{Med(?:al|alCompetition)[^}]*\}\}',
        dotAll: true,
      ).allMatches(wikitext);

      for (final block in medalBlocks) {
        final text = block.group(0)!;
        final year = RegExp(r'year\s*=\s*([^|\n}]+)', caseSensitive: false)
            .firstMatch(text)
            ?.group(1)
            ?.trim();
        final comp = RegExp(r'competition\s*=\s*([^|\n}]+)', caseSensitive: false)
            .firstMatch(text)
            ?.group(1)
            ?.trim();
        final event = RegExp(r'event\s*=\s*([^|\n}]+)', caseSensitive: false)
            .firstMatch(text)
            ?.group(1)
            ?.trim();
        final place = RegExp(r'\b(Gold|Silver|Bronze)\b', caseSensitive: false)
            .firstMatch(text)
            ?.group(1);

        if (comp == null || place == null) {
          continue;
        }

        var line = '${year ?? '?'} $place — $comp';
        if (event != null && event.isNotEmpty) {
          line += ' ($event)';
        }
        titles.add(line);
      }

      for (final line in wikitext.split('\n')) {
        final trimmed = line.trim();
        if (!trimmed.startsWith('*')) {
          continue;
        }
        if (!RegExp(
          r'WTT|World Championship|Olympic|Grand Smash|Singapore Smash|Contender|Cup Finals',
          caseSensitive: false,
        ).hasMatch(trimmed)) {
          continue;
        }
        if (RegExp(r'\b(19|20)\d{2}\b').hasMatch(trimmed)) {
          titles.add(trimmed.replaceFirst('*', '').trim());
        }
      }

      return titles;
    } catch (_) {
      return [];
    }
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
  });

  final String? week;
  final String? year;
}
