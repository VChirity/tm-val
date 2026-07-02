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
