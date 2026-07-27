import 'package:supabase_flutter/supabase_flutter.dart';

import '../config/supabase_config.dart';

/// Candidato retornado pela busca (nome ainda não hidratado / dados completos).
class PlayerCandidate {
  const PlayerCandidate({
    required this.ittfId,
    required this.name,
    required this.gender,
    this.countryCode,
    this.ranking,
    this.rankingPoints,
    this.photoUrl,
    this.alreadyAdded = false,
  });

  final String ittfId;
  final String name;
  final String gender;
  final String? countryCode;
  final int? ranking;
  final int? rankingPoints;
  final String? photoUrl;
  final bool alreadyAdded;

  factory PlayerCandidate.fromJson(Map<String, dynamic> json) {
    return PlayerCandidate(
      ittfId: json['ittf_id'].toString(),
      name: json['name'] as String,
      gender: json['gender'] as String,
      countryCode: json['country_code'] as String?,
      ranking: (json['ranking'] as num?)?.toInt(),
      rankingPoints: (json['ranking_points'] as num?)?.toInt(),
      photoUrl: json['photo_url'] as String?,
      alreadyAdded: json['already_added'] as bool? ?? false,
    );
  }
}

/// Serviço de busca/hidratação de atletas via Edge Function `wtt-player-lookup`.
///
/// Permite adicionar à home qualquer atleta do registro de ~1000 nomes
/// (incluindo brasileiros fora do top 100) buscando pelo nome.
class WttPlayerLookupService {
  WttPlayerLookupService({SupabaseClient? client})
      : _client = client ?? SupabaseConfig.client;

  final SupabaseClient _client;

  Future<List<PlayerCandidate>> search({
    required String query,
    String? gender,
  }) async {
    final response = await _client.functions.invoke(
      'wtt-player-lookup',
      body: {
        'action': 'search',
        'query': query,
        if (gender != null) 'gender': gender,
      },
    );

    if (response.status != 200) {
      throw Exception(response.data?.toString() ?? 'Falha na busca');
    }

    final data = Map<String, dynamic>.from(response.data as Map);
    if (data['error'] != null) {
      throw Exception(data['error'].toString());
    }

    final candidates = (data['candidates'] as List?) ?? [];
    return candidates
        .map((c) => PlayerCandidate.fromJson(Map<String, dynamic>.from(c as Map)))
        .toList();
  }

  /// Busca dados completos (perfil + títulos) e insere/atualiza o atleta na
  /// tabela `athletes`, marcando `listed_in_home = true`.
  Future<Map<String, dynamic>> hydrate({
    required String ittfId,
    String? gender,
  }) async {
    final response = await _client.functions.invoke(
      'wtt-player-lookup',
      body: {
        'action': 'hydrate',
        'ittf_id': ittfId,
        if (gender != null) 'gender': gender,
      },
    );

    if (response.status != 200) {
      throw Exception(response.data?.toString() ?? 'Falha ao carregar atleta');
    }

    final data = Map<String, dynamic>.from(response.data as Map);
    if (data['error'] != null) {
      throw Exception(data['error'].toString());
    }

    return Map<String, dynamic>.from(data['athlete'] as Map);
  }
}
