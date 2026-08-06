import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../config/theme.dart';
import '../services/auth_service.dart';

/// Fast local re-entry PIN lock.
///
/// The PIN only unlocks an *existing valid session* — it is never sent to
/// the backend and never grants a new session. After
/// [AuthService.maxPinAttempts] failed attempts (or a manual "sign in
/// differently") the session is cleared and the auth gate falls back to the
/// full passkey / sign-in flow.
///
/// TRADING MODE: never add tap-based execution here.
class PinLockScreen extends StatefulWidget {
  final Future<void> Function() onAuthenticated;
  final Future<void> Function() onLockedOut;

  const PinLockScreen({
    super.key,
    required this.onAuthenticated,
    required this.onLockedOut,
  });

  @override
  State<PinLockScreen> createState() => _PinLockScreenState();
}

class _PinLockScreenState extends State<PinLockScreen> {
  final AuthService _auth = AuthService.instance;
  final List<String> _digits = [];
  bool _busy = false;
  String? _error;
  int _attempts = 0;

  void _enterDigit(String digit) {
    if (_busy || _digits.length >= 6) return;
    setState(() {
      _digits.add(digit);
      _error = null;
    });
    if (_digits.length >= 4) _check();
  }

  void _backspace() {
    if (_busy) return;
    setState(() {
      if (_digits.isNotEmpty) _digits.removeLast();
      _error = null;
    });
  }

  Future<void> _check() async {
    final pin = _digits.join();
    setState(() => _busy = true);
    final ok = await _auth.verifyPin(pin);
    if (!mounted) return;
    if (ok) {
      await widget.onAuthenticated();
      return;
    }
    _attempts += 1;
    setState(() {
      _busy = false;
      _digits.clear();
      if (_attempts >= _auth.maxPinAttempts) {
        _error =
            'Too many failed attempts. Signing you out — please sign in again.';
      } else {
        _error = 'Wrong PIN. ${_auth.maxPinAttempts - _attempts} attempts left.';
      }
    });
    if (_attempts >= _auth.maxPinAttempts) {
      await _auth.clearSession();
      await widget.onLockedOut();
    }
  }

  Future<void> _signInDifferently() async {
    await _auth.logout();
    await widget.onLockedOut();
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final displayName = _auth.displayName ?? 'Trader';
    return Scaffold(
      body: SafeArea(
        child: Center(
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(AppTokens.spaceXl),
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                CircleAvatar(
                  radius: 34,
                  backgroundColor: scheme.primary.withValues(alpha: 0.15),
                  child: Icon(Icons.lock_outline_rounded,
                      size: 34, color: scheme.primary),
                ),
                const SizedBox(height: AppTokens.spaceLg),
                Text(
                  'Welcome back, $displayName',
                  style: Theme.of(context).textTheme.titleLarge?.copyWith(
                        fontWeight: FontWeight.w700,
                      ),
                ),
                const SizedBox(height: AppTokens.spaceXs),
                Text(
                  'Enter your PIN to unlock',
                  style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                        color: scheme.onSurfaceVariant,
                      ),
                ),
                const SizedBox(height: AppTokens.spaceXl),

                // Dots
                Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: List.generate(6, (i) {
                    final filled = i < _digits.length;
                    return AnimatedContainer(
                      duration: const Duration(milliseconds: 120),
                      margin: const EdgeInsets.symmetric(horizontal: 6),
                      width: 16,
                      height: 16,
                      decoration: BoxDecoration(
                        shape: BoxShape.circle,
                        color: filled
                            ? scheme.primary
                            : scheme.outlineVariant,
                      ),
                    );
                  }),
                ),
                const SizedBox(height: AppTokens.spaceLg),

                if (_error != null) ...[
                  Text(
                    _error!,
                    textAlign: TextAlign.center,
                    style: const TextStyle(
                      color: AppColors.bear,
                      fontSize: 13,
                      height: 1.35,
                    ),
                  ),
                  const SizedBox(height: AppTokens.spaceLg),
                ],

                // Numeric pad
                _buildKeypad(scheme),

                const SizedBox(height: AppTokens.spaceLg),
                TextButton(
                  onPressed: _busy ? null : _signInDifferently,
                  child: const Text('Sign in differently'),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildKeypad(ColorScheme scheme) {
    const keys = [
      '1', '2', '3',
      '4', '5', '6',
      '7', '8', '9',
      '', '0', 'back',
    ];
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        for (var row = 0; row < 4; row++)
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 5),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                for (var col = 0; col < 3; col++)
                  _buildKey(keys[row * 3 + col], scheme),
              ],
            ),
          ),
      ],
    );
  }

  Widget _buildKey(String label, ColorScheme scheme) {
    final isBack = label == 'back';
    final isEmpty = label.isEmpty;
    return SizedBox(
      width: 76,
      height: 64,
      child: isEmpty
          ? const SizedBox.shrink()
          : TextButton(
              onPressed: _busy
                  ? null
                  : () => isBack ? _backspace() : _enterDigit(label),
              style: TextButton.styleFrom(
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(AppTokens.radiusControl),
                ),
                backgroundColor: scheme.surfaceContainerHighest,
              ),
              child: isBack
                  ? Icon(Icons.backspace_outlined,
                      size: 22, color: scheme.onSurfaceVariant)
                  : Text(
                      label,
                      style: TextStyle(
                        fontSize: 22,
                        fontWeight: FontWeight.w600,
                        color: scheme.onSurface,
                      ),
                    ),
            ),
    );
  }
}
