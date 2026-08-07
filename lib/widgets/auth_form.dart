import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../config/theme.dart';
import '../services/auth_service.dart';

/// Reusable sign-up / sign-in form used by [AuthScreen] and the onboarding
/// account step.
///
/// Credential strategy:
///  * HTTPS backend → passkeys (WebAuthn) are the primary credential; the
///    ceremony runs right after sign-up and on sign-in.
///  * Plain-HTTP / IP-address backend (WebAuthn cannot run) → a device-bound
///    secret is sent at sign-up and used for sign-in on the same device.
///
/// [onAuthenticated] fires once a valid session exists (a PIN may be
/// offered first after sign-up).
///
/// TRADING MODE: never add tap-based execution here.
class AuthForm extends StatefulWidget {
  final Future<void> Function() onAuthenticated;

  const AuthForm({super.key, required this.onAuthenticated});

  @override
  State<AuthForm> createState() => _AuthFormState();
}

class _AuthFormState extends State<AuthForm> {
  final AuthService _auth = AuthService.instance;
  final _emailController = TextEditingController();
  final _displayNameController = TextEditingController();

  bool _isSignUp = true;
  bool _busy = false;
  String? _error;
  String? _passkeyNote;

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
        // Passkey registration is best-effort: on non-HTTPS backends it is
        // skipped entirely (device secret is the credential there), and any
        // ceremony failure must not block sign-up.
        if (_auth.passkeysSupported) {
          try {
            await _auth.registerPasskey();
          } on AuthException catch (e) {
            if (e.isCancelled) {
              setState(() => _passkeyNote = 'Passkey setup was skipped.');
            } else {
              setState(() => _passkeyNote = 'Passkey setup failed, but you are signed in.');
            }
          }
        }
        await _offerPinSetup();
      } else {
        final account = await _auth.signIn(email);
        final hasPasskey = account['has_passkey'] == true;
        if (hasPasskey && _auth.passkeysSupported) {
          await _auth.authenticatePasskey(account['user_id'] as String);
        } else {
          await _auth.signInWithDeviceSecret(email);
        }
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
      builder: (ctx) => const PinSetupDialog(),
    );
    if (pin != null) {
      await _auth.setPin(pin);
    }
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
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
            disabledBackgroundColor: scheme.primary.withValues(alpha: 0.4),
            padding: const EdgeInsets.symmetric(vertical: AppTokens.spaceLg),
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(AppTokens.radiusControl),
            ),
          ),
          child: _busy
              ? const SizedBox(
                  width: 22,
                  height: 22,
                  child: CircularProgressIndicator(
                    strokeWidth: 2.5,
                    valueColor: AlwaysStoppedAnimation<Color>(AppColors.onAmber),
                  ),
                )
              : Text(
                  _isSignUp ? 'Create account' : 'Sign in',
                  style: const TextStyle(
                    fontWeight: FontWeight.w700,
                    fontSize: 15,
                  ),
                ),
        ),

        const SizedBox(height: AppTokens.spaceLg),
        Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Icon(
              _auth.passkeysSupported
                  ? Icons.fingerprint_rounded
                  : Icons.phonelink_lock_rounded,
              size: 16,
              color: scheme.onSurfaceVariant,
            ),
            const SizedBox(width: AppTokens.spaceXs),
            Expanded(
              child: Text(
                _credentialHint(),
                style: Theme.of(context).textTheme.bodySmall?.copyWith(
                      color: scheme.onSurfaceVariant,
                      height: 1.4,
                    ),
              ),
            ),
          ],
        ),
        if (_passkeyNote != null) ...[
          const SizedBox(height: AppTokens.spaceSm),
          Text(
            _passkeyNote!,
            style: Theme.of(context).textTheme.bodySmall?.copyWith(
                  color: AppColors.amber,
                ),
          ),
        ],
      ],
    );
  }

  String _credentialHint() {
    if (_auth.passkeysSupported) {
      return _isSignUp
          ? 'You will create a passkey (biometric / device credential) right '
              'after signing up. It is your primary sign-in method.'
          : 'Sign in unlocks with your passkey. A PIN is only a fast local '
              're-entry shortcut on this device.';
    }
    return _isSignUp
        ? 'Passkeys need a secure (HTTPS) connection, so this build signs '
            'you in with a credential stored securely on this device.'
        : 'Sign in with your email. This device unlocks automatically; a PIN '
            'is only a fast local re-entry shortcut.';
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
class PinSetupDialog extends StatefulWidget {
  const PinSetupDialog({super.key});

  @override
  State<PinSetupDialog> createState() => _PinSetupDialogState();
}

class _PinSetupDialogState extends State<PinSetupDialog> {
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
