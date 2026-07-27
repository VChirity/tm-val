import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import 'package:supabase_flutter/supabase_flutter.dart';

import '../config/supabase_config.dart';

class WttSyncResult {
  const WttSyncResult({
    required this.athletesSynced,
    required this.rankingWeek,
    required this.rankingYear,
    required this.hasUpdates,
    required this.athletesChanged,
    required this.athletesChecked,
    this.titlesChanged = 0,
  });

  final int athletesSynced;
  final String? rankingWeek;
  final String? rankingYear;
  final bool hasUpdates;
  final int athletesChanged;
  final int athletesChecked;
  final int titlesChanged;
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

  static const _athletesPerGender = 100;
  static const _totalAthletes = 200;
  static const _webBatchSize = 25;

  Future<WttSyncResult> syncFromWtt({
    void Function(String message, double progress, {String? subtitle})?
        onProgress,
  }) async {
    if (kIsWeb) {
      return _syncViaEdgeFunction(onProgress);
    }

    return _syncFastLocal(onProgress);
  }

  Future<WttSyncResult> _syncViaEdgeFunction(
    void Function(String message, double progress, {String? subtitle})?
        onProgress,
  ) async {
    onProgress?.call('Atualizando rankings...', 0.05);

    final rankingResponse = await _client.functions.invoke(
      'sync-wtt',
      body: const {'fast': true},
    );

    if (rankingResponse.status != 200) {
      final details = rankingResponse.data?.toString() ?? 'sem detalhes';
      throw Exception('Falha ao atualizar rankings ($details)');
    }

    final rankingData =
        Map<String, dynamic>.from(rankingResponse.data as Map);
    if (rankingData['error'] != null) {
      throw Exception(rankingData['error'].toString());
    }

    // Temporário: Atualizar só sincroniza ranking (fast).
    // Enrichment de títulos ficou desligado até o merge estar comprovado seguro.
    final rankingChanged = _parseInt(rankingData['athletesChanged']) ?? 0;
    final rankingWeek = rankingData['rankingWeek']?.toString();
    final rankingYear = rankingData['rankingYear']?.toString();
    final total = _parseInt(rankingData['total']) ??
        _parseInt(rankingData['processed']) ??
        _totalAthletes;

    final summary = rankingChanged > 0
        ? '$total atletas — $rankingChanged ranking(s) alterados'
        : '$total atletas verificados — nada mudou';

    onProgress?.call(summary, 1);

    return WttSyncResult(
      athletesSynced: rankingChanged,
      rankingWeek: rankingWeek,
      rankingYear: rankingYear,
      hasUpdates: rankingChanged > 0 || rankingData['hasUpdates'] == true,
      athletesChanged: rankingChanged,
      athletesChecked: total,
      titlesChanged: 0,
    );
  }

  Future<WttSyncResult> _syncFastLocal(
    void Function(String message, double progress, {String? subtitle})?
        onProgress,
  ) async {
    onProgress?.call('Consultando rankings na WTT...', 0.1);

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
      throw Exception(
        'Falha ao buscar rankings WTT (${rankingResponse.statusCode})',
      );
    }

    onProgress?.call('Comparando com o banco de dados...', 0.5);

    final payload = jsonDecode(rankingResponse.body) as Map<String, dynamic>;
    final allRankings = (payload['Result'] as List?) ?? [];
    final remoteMeta = _extractRankingMeta(allRankings);

    final athletesToUpsert = <Map<String, dynamic>>[];
    var changedCount = 0;
    var checked = 0;

    for (final subEvent in ['MS', 'WS']) {
      final gender = subEvent == 'MS' ? 'male' : 'female';
      final rows = _collectGenderRankings(allRankings, subEvent);

      for (final row in rows) {
        checked++;
        final name = row['PlayerName']?.toString() ?? '';
        final key = _athleteKey(name, gender);
        final existing = existingByKey[key];
        final record = _buildAthleteRecordFast(row, gender, existing);

        if (_recordChangedFast(existing, record)) {
          changedCount++;
          athletesToUpsert.add(record);
        }

        onProgress?.call(
          'Verificando $checked/$_totalAthletes atletas '
          '(${((checked / _totalAthletes) * 100).round()}%)...',
          0.5 + (checked / _totalAthletes) * 0.45,
          subtitle: name,
        );
      }
    }

    if (athletesToUpsert.isNotEmpty) {
      onProgress?.call('Salvando alterações no Supabase...', 0.96);
      await _client.from('athletes').upsert(
        athletesToUpsert,
        onConflict: 'name,gender',
      );
    }

    onProgress?.call(
      changedCount > 0
          ? '$checked atletas verificados, $changedCount alterados'
          : '$checked atletas verificados, nada mudou',
      1,
    );

    return WttSyncResult(
      athletesSynced: athletesToUpsert.length,
      rankingWeek: remoteMeta?.week,
      rankingYear: remoteMeta?.year,
      hasUpdates: changedCount > 0 || existingRows.isEmpty,
      athletesChanged: changedCount,
      athletesChecked: checked,
    );
  }

  String _athleteKey(String name, String gender) => '$name|$gender';

  Future<List<Map<String, dynamic>>> _fetchExistingAthletes() async {
    final rows = await _client.from('athletes').select(
      'name,gender,ranking,ranking_points,age,height,hand,championships_won,ittf_id,photo_url,profile_hydrated',
    );
    return (rows as List)
        .map((row) => Map<String, dynamic>.from(row as Map))
        .toList();
  }

  bool _recordChangedFast(
    Map<String, dynamic>? existing,
    Map<String, dynamic> record,
  ) {
    if (existing == null) {
      return true;
    }

    return existing['ranking'] != record['ranking'] ||
        existing['ranking_points'] != record['ranking_points'] ||
        existing['ittf_id']?.toString() != record['ittf_id']?.toString() ||
        existing['photo_url']?.toString() != record['photo_url']?.toString();
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
    int limit = _athletesPerGender,
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

  Map<String, dynamic> _buildAthleteRecordFast(
    Map<String, dynamic> rankingRow,
    String gender,
    Map<String, dynamic>? existing,
  ) {
    final name = rankingRow['PlayerName']?.toString() ?? '';
    final ittfId = rankingRow['IttfId']?.toString() ?? '';
    final rankingPhoto = _photoFromRankingRow(rankingRow);
    final existingPhoto = existing?['photo_url']?.toString();

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
      'age': _parseInt(rankingRow['Age']) ?? existing?['age'],
      'height': existing?['height'],
      'hand': existing?['hand'],
      'championships_won': existing?['championships_won'] ?? [],
      'photo_url': rankingPhoto ?? existingPhoto,
      'listed_in_home': true,
      'profile_hydrated': existing?['profile_hydrated'] ?? true,
      'updated_at': DateTime.now().toUtc().toIso8601String(),
    };
  }

  String? _photoFromRankingRow(Map<String, dynamic> row) {
    final candidate = row['HeadshotR'] ??
        row['HeadShot'] ??
        row['HeadshotL'] ??
        row['PlayerPhoto'] ??
        row['PhotoUrl'] ??
        row['HeadshotUrl'];
    return _normalizePhotoUrl(candidate?.toString());
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
}

class _RankingMeta {
  const _RankingMeta({
    required this.week,
    required this.year,
  });

  final String? week;
  final String? year;
}
