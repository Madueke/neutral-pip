import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../config/theme.dart';
import '../services/auth_service.dart';
import 'app_shell.dart';
import 'auth_screen.dart';
import 'pin_lock_screen.dart';

/// Decides what the user sees after onboarding / splash:
///
///  * No trading backend configured → straight into the app (dev/offline
///    mode; nothing auth-gated exists without a backend).
///  * Backend configured + valid session + PIN set → [PinLockScreen].
///  * Backend configured + valid session, no PIN → [AppShell].
///  * Backend configured, no valid session → [AuthScreen].
///
/// Sessions are validated against GET /auth/session on every cold start so
/// an expired/revoked token always falls back to full passkey / sign-in.
///
/// TRADING MODE: never add tap-based execution here.
class AuthGate extends StatefulWidget {
  const AuthGate({super.key});

  @override
  State<AuthGate> createState() => _AuthGateState();
}

enum _AuthState { loading, shell, signIn, pin }

class _AuthGateState extends State<AuthGate> {
  final AuthService _auth = AuthService.instance;
  _AuthState _state = _AuthState.loading;

  @override
  void initState() {
    super.initState();
    _bootstrap();
  }

  Future<void> _bootstrap() async {
    await _auth.init();
    final prefs = await SharedPreferences.getInstance();
    final backendConfigured =
        (prefs.getString('trading_backend_url') ?? '').isNotEmpty;
    if (!backendConfigured) {
      if (mounted) setState(() => _state = _AuthState.shell);
      return;
    }
    final session = await _auth.restoreSession();
    if (!mounted) return;
    if (session == null) {
      setState(() => _state = _AuthState.signIn);
    } else if (_auth.hasPin) {
      setState(() => _state = _AuthState.pin);
    } else {
      setState(() => _state = _AuthState.shell);
    }
  }

  Future<void> _onAuthenticated() async {
    if (!mounted) return;
    // Fresh session: prefer PIN lock when one is configured, otherwise shell.
    if (_auth.hasPin) {
      setState(() => _state = _AuthState.pin);
    } else {
      setState(() => _state = _AuthState.shell);
    }
  }

  Future<void> _onLockedOut() async {
    if (!mounted) return;
    setState(() => _state = _AuthState.signIn);
  }

  @override
  Widget build(BuildContext context) {
    switch (_state) {
      case _AuthState.loading:
        return Scaffold(
          backgroundColor: Theme.of(context).scaffoldBackgroundColor,
          body: Center(
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Image.asset(
                  'assets/splash/logo_transparent.png',
                  width: 72,
                  height: 72,
                ),
                const SizedBox(height: AppTokens.spaceLg),
                const CircularProgressIndicator(
                  strokeWidth: 2.5,
                  valueColor: AlwaysStoppedAnimation<Color>(AppColors.amber),
                ),
              ],
            ),
          ),
        );
      case _AuthState.shell:
        return const AppShell();
      case _AuthState.signIn:
        return AuthScreen(onAuthenticated: _onAuthenticated);
      case _AuthState.pin:
        return PinLockScreen(
          onAuthenticated: _onAuthenticated,
          onLockedOut: _onLockedOut,
        );
    }
  }
}
