import 'package:flutter/material.dart';

import '../config/theme.dart';
import '../widgets/auth_form.dart';

/// Sign up / sign in for Trading Mode.
///
/// The actual form (credential strategy, PIN offer) lives in [AuthForm];
/// this screen adds the branded header and hands control back to the auth
/// gate via [onAuthenticated] once a valid session exists.
///
/// TRADING MODE: never add tap-based execution here.
class AuthScreen extends StatefulWidget {
  final Future<void> Function() onAuthenticated;

  const AuthScreen({super.key, required this.onAuthenticated});

  @override
  State<AuthScreen> createState() => _AuthScreenState();
}

class _AuthScreenState extends State<AuthScreen> {
  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Scaffold(
      body: SafeArea(
        child: Center(
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(AppTokens.spaceXl),
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 420),
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  // Brand header
                  Align(
                    alignment: Alignment.center,
                    child: Image.asset(
                      'assets/splash/logo_transparent.png',
                      width: 84,
                      height: 84,
                    ),
                  ),
                  const SizedBox(height: AppTokens.spaceLg),
                  Text(
                    'Neutral Pip',
                    textAlign: TextAlign.center,
                    style: Theme.of(context).textTheme.headlineSmall?.copyWith(
                          fontWeight: FontWeight.w700,
                          color: scheme.primary,
                        ),
                  ),
                  const SizedBox(height: AppTokens.spaceXs),
                  Text(
                    'Sign in to your trading account',
                    textAlign: TextAlign.center,
                    style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                          color: scheme.onSurfaceVariant,
                        ),
                  ),
                  const SizedBox(height: AppTokens.spaceXl),
                  AuthForm(onAuthenticated: widget.onAuthenticated),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}
