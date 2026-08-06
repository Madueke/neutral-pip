import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../config/theme.dart';
import '../services/auth_service.dart';
import '../widgets/logo_loader.dart';

/// Sign up / sign in for Trading Mode.
///
/// Passkeys (WebAuthn via Android Credential Manager) are the primary
/// credential. On first sign up the app immediately runs the passkey
/// registration ceremony (mandatory, not skippable), then offers PIN setup.
/// Email sign-in alone never opens a session: it resolves the account and
/// runs the passkey challenge instead.
///
/// The [onAuthenticated] callback hands control back to the auth gate once a
/// valid session exists (with or without a PIN configured).
///
/// TRADING MODE: never add tap-based execution here.
class AuthScreen extends StatefulWidget {
  final Future<void> Function() onAuthenticated;

  const AuthScreen({super.key, required this.onAuthenticated});

  @override
  State<AuthScreen> createState() => _AuthScreenState();
}

class _AuthScreenState extends State<AuthScreen> {
  final AuthService _auth = AuthService.instance;
  final _emailController = TextEditingController();
  final _displayNameController = TextEditingController();

  bool _isSignUp = true;
  bool _busy = false;
  String? _error;

  @override
  void dispose() {
    _emailController.dispose();
    _displayNameController.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    final email = _emailController.text.trim();
    if (!email.contains('@')) {
      setState(() => _error = 'Enter a valid email address.');
      return;
    }
    if (_isSignUp && _displayNameController.text.trim().isEmpty) {
      setState(() => _error = 'Enter a display name.');
      return;
    }
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      if (_isSignUp) {
        await _auth.signUp(
          email: email,
          displayName: _displayNameController.text.trim(),
        );
        // Mandatory passkey registration right after first sign up.
        await _auth.registerPasskey();
        await _offerPinSetup();
      } else {
        final account = await _auth.signIn(email);
        if (account['has_passkey'] != true) {
          setState(() {
            _error =
                'No passkey is registered for this account. Sign up again on '
                'this device to create one.';
          });
          return;
        }
        await _auth.authenticatePasskey(account['user_id'] as String);
      }
      if (mounted) await widget.onAuthenticated();
    } on AuthException catch (e) {
      if (!e.isCancelled && mounted) setState(() => _error = e.message);
    } catch (e) {
      if (mounted) {
        setState(() => _error = 'Something went wrong: $e');
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  /// Offer a 4-6 digit PIN for fast re-entry. Skippable — it is a local
  /// convenience, not a credential.
  Future<void> _offerPinSetup() async {
    if (!mounted) return;
    final pin = await showDialog<String>(
      context: context,
      barrierDismissible: false,
      builder: (ctx) => const _PinSetupDialog(),
    );
    if (pin != null) {
      await _auth.setPin(pin);
    }
  }

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

                  // Mode toggle
                  SegmentedButton<bool>(
                    segments: const [
                      ButtonSegment(value: true, label: Text('Sign up')),
                      ButtonSegment(value: false, label: Text('Sign in')),
                    ],
                    selected: {_isSignUp},
                    onSelectionChanged: _busy
                        ? null
                        : (selection) => setState(() {
                              _isSignUp = selection.first;
                              _error = null;
                            }),
                  ),
                  const SizedBox(height: AppTokens.spaceXl),

                  // Email
                  TextField(
                    controller: _emailController,
                    enabled: !_busy,
                    keyboardType: TextInputType.emailAddress,
                    autocorrect: false,
                    decoration: _inputDecoration(
                      scheme,
                      label: 'Email',
                      hint: 'you@example.com',
                      icon: Icons.mail_outline_rounded,
                    ),
                  ),
                  if (_isSignUp) ...[
                    const SizedBox(height: AppTokens.spaceMd),
                    TextField(
                      controller: _displayNameController,
                      enabled: !_busy,
                      textCapitalization: TextCapitalization.words,
                      decoration: _inputDecoration(
                        scheme,
                        label: 'Display name',
                        hint: 'How should we call you?',
                        icon: Icons.person_outline_rounded,
                      ),
                    ),
                  ],

                  if (_error != null) ...[
                    const SizedBox(height: AppTokens.spaceLg),
                    Container(
                      padding: const EdgeInsets.all(AppTokens.spaceMd),
                      decoration: BoxDecoration(
                        color: AppColors.bear.withValues(alpha: 0.12),
                        borderRadius: BorderRadius.circular(AppTokens.radiusControl),
                        border: Border.all(
                          color: AppColors.bear.withValues(alpha: 0.4),
                        ),
                      ),
                      child: Row(
                        children: [
                          const Icon(Icons.error_outline_rounded,
                              color: AppColors.bear, size: 20),
                          const SizedBox(width: AppTokens.spaceSm),
                          Expanded(
                            child: Text(
                              _error!,
                              style: TextStyle(
                                color: AppColors.bear,
                                fontSize: 13,
                                height: 1.35,
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],

                  const SizedBox(height: AppTokens.spaceXl),
                  FilledButton(
                    onPressed: _busy ? null : _submit,
                    style: FilledButton.styleFrom(
                      backgroundColor: scheme.primary,
                      foregroundColor: AppColors.onAmber,
                      disabledBackgroundColor:
                          scheme.primary.withValues(alpha: 0.4),
                      padding: const EdgeInsets.symmetric(
                        vertical: AppTokens.spaceLg,
                      ),
                      shape: RoundedRectangleBorder(
                        borderRadius:
                            BorderRadius.circular(AppTokens.radiusControl),
                      ),
                    ),
                    child: _busy
                        ? const SizedBox(
                            width: 22,
                            height: 22,
                            child: CircularProgressIndicator(
                              strokeWidth: 2.5,
                              valueColor:
                                  AlwaysStoppedAnimation<Color>(AppColors.onAmber),
                            ),
                          )
                        : Text(
                            _isSignUp ? 'Create account' : 'Sign in with passkey',
                            style: const TextStyle(
                              fontWeight: FontWeight.w700,
                              fontSize: 15,
                            ),
                          ),
                  ),

                  const SizedBox(height: AppTokens.spaceLg),
                  Row(
                    children: [
                      Icon(
                        Icons.fingerprint_rounded,
                        size: 16,
                        color: scheme.onSurfaceVariant,
                      ),
                      const SizedBox(width: AppTokens.spaceXs),
                      Expanded(
                        child: Text(
                          _isSignUp
                              ? 'You will create a passkey (biometric / device '
                                  'credential) right after signing up. It is your '
                                  'primary sign-in method.'
                              : 'Sign in unlocks with your passkey. A PIN is only '
                                  'a fast local re-entry shortcut on this device.',
                          style: Theme.of(context).textTheme.bodySmall?.copyWith(
                                color: scheme.onSurfaceVariant,
                                height: 1.4,
                              ),
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  InputDecoration _inputDecoration(
    ColorScheme scheme, {
    required String label,
    required String hint,
    required IconData icon,
  }) {
    return InputDecoration(
      labelText: label,
      hintText: hint,
      prefixIcon: Icon(icon, size: 18),
      filled: true,
      fillColor: scheme.surfaceContainerHighest,
      border: OutlineInputBorder(
        borderRadius: BorderRadius.circular(AppTokens.radiusControl),
        borderSide: BorderSide(color: scheme.outlineVariant),
      ),
      enabledBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(AppTokens.radiusControl),
        borderSide: BorderSide(color: scheme.outlineVariant),
      ),
      focusedBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(AppTokens.radiusControl),
        borderSide: BorderSide(color: scheme.primary, width: 1.5),
      ),
    );
  }
}

/// Compact PIN setup dialog (4-6 digits, numeric only).
class _PinSetupDialog extends StatefulWidget {
  const _PinSetupDialog();

  @override
  State<_PinSetupDialog> createState() => _PinSetupDialogState();
}

class _PinSetupDialogState extends State<_PinSetupDialog> {
  final _controller = TextEditingController();
  String? _error;

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  void _confirm() {
    final pin = _controller.text;
    if (!RegExp(r'^\d{4,6}$').hasMatch(pin)) {
      setState(() => _error = 'Enter 4 to 6 digits.');
      return;
    }
    Navigator.of(context).pop(pin);
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return AlertDialog(
      backgroundColor: AppColors.surfaceDark,
      title: const Text('Set a fast re-entry PIN'),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'Optional: unlock the app on this device with a 4-6 digit PIN '
            'instead of a full passkey prompt. It only works while your '
            'session is valid.',
            style: TextStyle(color: scheme.onSurfaceVariant, fontSize: 13),
          ),
          const SizedBox(height: AppTokens.spaceLg),
          TextField(
            controller: _controller,
            autofocus: true,
            obscureText: true,
            keyboardType: TextInputType.number,
            maxLength: 6,
            inputFormatters: [FilteringTextInputFormatter.digitsOnly],
            decoration: InputDecoration(
              labelText: 'PIN',
              hintText: '4-6 digits',
              counterText: '',
              errorText: _error,
              filled: true,
              fillColor: scheme.surfaceContainerHighest,
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(AppTokens.radiusControl),
              ),
            ),
          ),
        ],
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('Skip'),
        ),
        FilledButton(
          onPressed: _confirm,
          style: FilledButton.styleFrom(backgroundColor: scheme.primary),
          child: const Text('Save PIN'),
        ),
      ],
    );
  }
}

/// Reusable branded full-screen loading state for auth transitions.
class AuthLoading extends StatelessWidget {
  final String message;
  const AuthLoading({super.key, required this.message});

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Scaffold(
      body: Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            const LogoLoader(size: 72),
            const SizedBox(height: AppTokens.spaceLg),
            Text(
              message,
              style: TextStyle(color: scheme.onSurfaceVariant, fontSize: 14),
            ),
          ],
        ),
      ),
    );
  }
}
