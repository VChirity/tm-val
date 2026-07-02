import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import 'package:supabase_flutter/supabase_flutter.dart';

import '../config/supabase_config.dart';

class HeadToHeadSummary {
  const HeadToHeadSummary({
    required this.totalMatches,
    required this.player1Wins,
    required this.player2Wins,
    required this.player1Name,
    required this.player2Name,
  });

  final int totalMatches;
  final int player1Wins;
  final int player2Wins;
  final String player1Name;
  final String player2Name;
}

class WttHeadToHeadService {
  WttHeadToHeadService({SupabaseClient? client, http.Client? httpClient})
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

  static const _h2hUrl =
      'https://wttcmsapigateway-new.azure-api.net/ttu/Players/GetPlayersHeadToHead';

  Future<HeadToHeadSummary?> fetchSummary({
    required String player1IttfId,
    required String player2IttfId,
    required String player1Name,
    required String player2Name,
  }) async {
    if (kIsWeb) {
      return _fetchViaEdgeFunction(
        player1IttfId: player1IttfId,
        player2IttfId: player2IttfId,
        player1Name: player1Name,
        player2Name: player2Name,
      );
    }

    final uri = Uri.parse(_h2hUrl).replace(
      queryParameters: {
        'Player1': player1IttfId,
        'Player2': player2IttfId,
        'EventId': '0',
        'MatchId': '0',
        'q': '${DateTime.now().millisecondsSinceEpoch}',
      },
    );

    final response = await _http.get(uri, headers: _headers);
    if (response.statusCode != 200) {
      return null;
    }

    final payload = jsonDecode(response.body) as Map<String, dynamic>;
    final result = (payload['Result'] as List?) ?? [];
    if (result.isEmpty) {
      return null;
    }

    final row = Map<String, dynamic>.from(result.first as Map);
    return HeadToHeadSummary(
      totalMatches: _parseInt(row['TotalMatchesPlayed']) ?? 0,
      player1Wins: _parseInt(row['Player1Win']) ?? 0,
      player2Wins: _parseInt(row['Player2Win']) ?? 0,
      player1Name: player1Name,
      player2Name: player2Name,
    );
  }

  Future<HeadToHeadSummary?> _fetchViaEdgeFunction({
    required String player1IttfId,
    required String player2IttfId,
    required String player1Name,
    required String player2Name,
  }) async {
    final response = await _client.functions.invoke(
      'wtt-h2h',
      body: {
        'player1': player1IttfId,
        'player2': player2IttfId,
      },
    );

    if (response.status != 200 || response.data == null) {
      return null;
    }

    final payload = Map<String, dynamic>.from(response.data as Map);
    final result = (payload['Result'] as List?) ?? [];
    if (result.isEmpty) {
      return null;
    }

    final row = Map<String, dynamic>.from(result.first as Map);
    return HeadToHeadSummary(
      totalMatches: _parseInt(row['TotalMatchesPlayed']) ?? 0,
      player1Wins: _parseInt(row['Player1Win']) ?? 0,
      player2Wins: _parseInt(row['Player2Win']) ?? 0,
      player1Name: player1Name,
      player2Name: player2Name,
    );
  }

  int? _parseInt(Object? value) {
    if (value == null || '$value'.isEmpty) {
      return null;
    }
    return int.tryParse('${double.tryParse('$value')}');
  }
}
