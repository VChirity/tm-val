import 'package:supabase_flutter/supabase_flutter.dart';

import '../config/supabase_config.dart';

/// Autenticação via Supabase Auth — a senha da Valesca desbloqueia o app e as gravações.
class AppAuthService {
  AppAuthService({SupabaseClient? client})
      : _client = client ?? SupabaseConfig.client;

  final SupabaseClient _client;

  static const appEmail = 'victorchirity@colegioequacao.com';

  Session? get currentSession => _client.auth.currentSession;

  bool get isAuthenticated => currentSession != null;

  Stream<AuthState> get authStateChanges => _client.auth.onAuthStateChange;

  Future<void> restoreSession() async {
    await _client.auth.refreshSession();
  }

  Future<void> signInWithPassword(String password) async {
    final response = await _client.auth.signInWithPassword(
      email: appEmail,
      password: password.trim(),
    );

    if (response.session == null) {
      throw AuthException('Não foi possível autenticar.');
    }
  }

  Future<void> signOut() async {
    await _client.auth.signOut();
  }
}
