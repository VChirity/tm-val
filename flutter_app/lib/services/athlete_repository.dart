import 'package:supabase_flutter/supabase_flutter.dart';

import '../config/supabase_config.dart';
import '../models/athlete.dart';
import '../models/athlete_note.dart';

class AthleteRepository {
  AthleteRepository({SupabaseClient? client})
      : _client = client ?? SupabaseConfig.client;

  final SupabaseClient _client;

  /// Colunas usadas na home: evita `championships_won` (pode ser grande em
  /// atletas com muitos títulos) para acelerar o carregamento inicial.
  static const _homeColumns =
      'id,name,gender,ranking,ranking_points,age,height,hand,ittf_id,'
      'photo_url,country_code,listed_in_home,profile_hydrated,updated_at';

  static const _homeColumnsLegacy =
      'id,name,gender,ranking,ranking_points,age,height,hand,ittf_id,'
      'photo_url,updated_at';

  Future<List<Athlete>> fetchAthletes({required String gender}) async {
    List rows;
    try {
      rows = await _client
          .from('athletes')
          .select(_homeColumns)
          .eq('gender', gender)
          .or('listed_in_home.eq.true,ranking.lte.100')
          .order('ranking', ascending: true, nullsFirst: false)
          .order('name', ascending: true) as List;
    } catch (_) {
      // Fallback se colunas novas ainda não existirem no schema remoto.
      rows = await _client
          .from('athletes')
          .select(_homeColumnsLegacy)
          .eq('gender', gender)
          .order('ranking', ascending: true)
          .order('name', ascending: true) as List;
    }
    final noteAthleteIds = await _fetchAthleteIdsWithNotes();

    return rows
        .map(
          (row) => Athlete.fromJson(
            Map<String, dynamic>.from(row as Map),
            hasNote: noteAthleteIds.contains(row['id']),
          ),
        )
        .toList();
  }

  Future<Athlete> fetchAthleteById(String athleteId) async {
    final row = await _client
        .from('athletes')
        .select('*')
        .eq('id', athleteId)
        .single();

    final notes = await fetchNotesByAthleteId(athleteId);
    return Athlete.fromJson(
      Map<String, dynamic>.from(row),
      hasNote: notes.isNotEmpty,
    );
  }

  Future<List<AthleteNote>> fetchNotesByAthleteId(String athleteId) async {
    final rows = await _client
        .from('athlete_notes')
        .select('*')
        .eq('athlete_id', athleteId)
        .order('updated_at', ascending: true);

    return (rows as List)
        .map((row) => AthleteNote.fromJson(Map<String, dynamic>.from(row as Map)))
        .where((note) => note.content.trim().isNotEmpty)
        .toList();
  }

  Future<AthleteNote> addNote({
    required String athleteId,
    required String content,
  }) async {
    final row = await _client
        .from('athlete_notes')
        .insert({
          'athlete_id': athleteId,
          'content': content.trim(),
        })
        .select('*')
        .single();

    return AthleteNote.fromJson(Map<String, dynamic>.from(row));
  }

  Future<AthleteNote> updateNote({
    required String noteId,
    required String content,
  }) async {
    final row = await _client
        .from('athlete_notes')
        .update({'content': content.trim()})
        .eq('id', noteId)
        .select('*')
        .single();

    return AthleteNote.fromJson(Map<String, dynamic>.from(row));
  }

  Future<void> deleteNote(String noteId) async {
    await _client.from('athlete_notes').delete().eq('id', noteId);
  }

  /// Atualiza a ficha técnica e marca os campos alterados em [manual_fields]
  /// para que o sync WTT não os sobrescreva.
  Future<Athlete> updateAthleteProfile({
    required String athleteId,
    int? rankingPoints,
    int? age,
    double? height,
    String? hand,
    String? shortBio,
    required Set<String> editedFields,
  }) async {
    final current = await _client
        .from('athletes')
        .select('manual_fields')
        .eq('id', athleteId)
        .single();

    final mergedManual = <String, dynamic>{};
    final existingManual = current['manual_fields'];
    if (existingManual is Map) {
      for (final entry in existingManual.entries) {
        if (entry.value == true) {
          mergedManual[entry.key.toString()] = true;
        }
      }
    }
    for (final field in editedFields) {
      mergedManual[field] = true;
    }

    final payload = <String, dynamic>{
      'manual_fields': mergedManual,
      'updated_at': DateTime.now().toUtc().toIso8601String(),
    };
    if (editedFields.contains('ranking_points')) {
      payload['ranking_points'] = rankingPoints;
    }
    if (editedFields.contains('age')) {
      payload['age'] = age;
    }
    if (editedFields.contains('height')) {
      payload['height'] = height;
    }
    if (editedFields.contains('hand')) {
      payload['hand'] = hand;
    }
    if (editedFields.contains('short_bio')) {
      payload['short_bio'] = shortBio;
    }

    final row = await _client
        .from('athletes')
        .update(payload)
        .eq('id', athleteId)
        .select('*')
        .single();

    final notes = await fetchNotesByAthleteId(athleteId);
    return Athlete.fromJson(
      Map<String, dynamic>.from(row),
      hasNote: notes.isNotEmpty,
    );
  }

  Future<List<Athlete>> searchAthletes({
    required String query,
    String? excludeId,
    int limit = 15,
  }) async {
    final trimmed = query.trim();
    if (trimmed.isEmpty) {
      return [];
    }

    final rows = await _client
        .from('athletes')
        .select('*')
        .ilike('name', '%$trimmed%')
        .not('ittf_id', 'is', null)
        .limit(limit);

    return (rows as List)
        .map((row) => Athlete.fromJson(Map<String, dynamic>.from(row as Map)))
        .where((athlete) => athlete.id != excludeId && athlete.ittfId != null)
        .toList();
  }

  Future<Set<String>> _fetchAthleteIdsWithNotes() async {
    // Só busca a coluna athlete_id (não content) para reduzir o payload;
    // o filtro de conteúdo vazio já é aplicado no servidor.
    final rows = await _client
        .from('athlete_notes')
        .select('athlete_id')
        .not('content', 'eq', '');

    return (rows as List)
        .map((row) => (row as Map)['athlete_id'] as String)
        .toSet();
  }
}

