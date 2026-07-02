import 'package:supabase_flutter/supabase_flutter.dart';

import '../config/supabase_config.dart';
import '../models/athlete.dart';
import '../models/athlete_note.dart';

class AthleteRepository {
  AthleteRepository({SupabaseClient? client})
      : _client = client ?? SupabaseConfig.client;

  final SupabaseClient _client;

  Future<List<Athlete>> fetchAthletes({required String gender}) async {
    final rows = await _client
        .from('athletes')
        .select('*')
        .eq('gender', gender)
        .order('ranking', ascending: true);
    final noteAthleteIds = await _fetchAthleteIdsWithNotes();

    return (rows as List)
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

    final note = await fetchNoteByAthleteId(athleteId);
    return Athlete.fromJson(
      Map<String, dynamic>.from(row),
      hasNote: note != null && note.content.trim().isNotEmpty,
    );
  }

  Future<AthleteNote?> fetchNoteByAthleteId(String athleteId) async {
    final rows = await _client
        .from('athlete_notes')
        .select('*')
        .eq('athlete_id', athleteId)
        .limit(1);

    if ((rows as List).isEmpty) {
      return null;
    }

    return AthleteNote.fromJson(
      Map<String, dynamic>.from(rows.first as Map),
    );
  }

  Future<AthleteNote> saveNote({
    required String athleteId,
    required String content,
    AthleteNote? existingNote,
  }) async {
    if (existingNote == null) {
      final row = await _client
          .from('athlete_notes')
          .insert({
            'athlete_id': athleteId,
            'content': content,
          })
          .select('*')
          .single();

      return AthleteNote.fromJson(Map<String, dynamic>.from(row));
    }

    final row = await _client
        .from('athlete_notes')
        .update({'content': content})
        .eq('id', existingNote.id)
        .select('*')
        .single();

    return AthleteNote.fromJson(Map<String, dynamic>.from(row));
  }

  Future<void> deleteNote(String noteId) async {
    await _client.from('athlete_notes').delete().eq('id', noteId);
  }

  Future<Set<String>> _fetchAthleteIdsWithNotes() async {
    final rows = await _client
        .from('athlete_notes')
        .select('athlete_id, content');

    return (rows as List)
        .where((row) {
          final content = (row as Map)['content']?.toString().trim() ?? '';
          return content.isNotEmpty;
        })
        .map((row) => (row as Map)['athlete_id'] as String)
        .toSet();
  }
}
