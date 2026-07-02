import 'package:supabase_flutter/supabase_flutter.dart';

import '../config/supabase_config.dart';
import '../models/broadcast_note.dart';

class BroadcastNoteRepository {
  BroadcastNoteRepository({SupabaseClient? client})
      : _client = client ?? SupabaseConfig.client;

  final SupabaseClient _client;

  Future<List<BroadcastNote>> fetchNotes() async {
    final rows = await _client
        .from('broadcast_notes')
        .select('*')
        .order('updated_at', ascending: true);

    return (rows as List)
        .map((row) => BroadcastNote.fromJson(Map<String, dynamic>.from(row as Map)))
        .where((note) => note.content.trim().isNotEmpty)
        .toList();
  }

  Future<BroadcastNote> addNote(String content) async {
    final row = await _client
        .from('broadcast_notes')
        .insert({'content': content.trim()})
        .select('*')
        .single();

    return BroadcastNote.fromJson(Map<String, dynamic>.from(row));
  }

  Future<BroadcastNote> updateNote({
    required String noteId,
    required String content,
  }) async {
    final row = await _client
        .from('broadcast_notes')
        .update({'content': content.trim()})
        .eq('id', noteId)
        .select('*')
        .single();

    return BroadcastNote.fromJson(Map<String, dynamic>.from(row));
  }

  Future<void> deleteNote(String noteId) async {
    await _client.from('broadcast_notes').delete().eq('id', noteId);
  }
}
