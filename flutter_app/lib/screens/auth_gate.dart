import 'package:flutter/material.dart';

import '../services/app_auth_service.dart';
import 'home_screen.dart';
import 'login_screen.dart';

class AuthGate extends StatefulWidget {
  const AuthGate({super.key});

  @override
  State<AuthGate> createState() => _AuthGateState();
}

class _AuthGateState extends State<AuthGate> {
  final _auth = AppAuthService();
  bool _ready = false;

  @override
  void initState() {
    super.initState();
    _bootstrap();
    _auth.authStateChanges.listen((_) {
      if (mounted) setState(() {});
    });
  }

  Future<void> _bootstrap() async {
    try {
      await _auth.restoreSession();
    } catch (_) {}
    if (mounted) {
      setState(() => _ready = true);
    }
  }

  @override
  Widget build(BuildContext context) {
    if (!_ready) {
      return const Scaffold(
        body: Center(child: CircularProgressIndicator()),
      );
    }

    if (!_auth.isAuthenticated) {
      return LoginScreen(onAuthenticated: () => setState(() {}));
    }

    return const HomeScreen();
  }
}
