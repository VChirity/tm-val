import 'package:flutter_dotenv/flutter_dotenv.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

class SupabaseConfig {
  static Future<void> initialize() async {
    await dotenv.load(fileName: 'assets/.env');

    final url = dotenv.env['SUPABASE_URL'];
    final anonKey = dotenv.env['SUPABASE_ANON_KEY'];

    if (url == null ||
        anonKey == null ||
        url.contains('[PROJECT_REF]') ||
        anonKey == 'your-anon-key') {
      throw StateError(
        'Configure SUPABASE_URL e SUPABASE_ANON_KEY em flutter_app/assets/.env',
      );
    }

    await Supabase.initialize(
      url: url,
      publishableKey: anonKey,
    );
  }

  static SupabaseClient get client => Supabase.instance.client;
}
