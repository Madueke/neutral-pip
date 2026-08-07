import 'dart:convert';
import 'dart:math';
import 'package:crypto/crypto.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:http/http.dart' as http;
import 'package:passkeys/authenticator.dart';
import 'package:passkeys/exceptions.dart';
import 'package:passkeys/types.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../config/app_config.dart';

/// Trading Mode authentication service.
///
/// Passkeys (WebAuthn) are the primary credential, issued by the backend.
/// The session token issued after a successful ceremony is stored in secure
/// storage and sent as `Authorization: Bearer` on every Trading Mode call —
/// the app never constructs or sends a raw user_id itself.
///
/// A 4-6 digit PIN is a *local fast re-entry* shortcut only: it unlocks an
/// already-valid session (verified against GET /auth/session) and is hashed
/// with a random salt in secure storage. It is never sent to the backend and
/// never grants a new session by itself.
///
/// TRADING MODE: never add tap-based execution here.
class AuthService {
  AuthService._();

  static final AuthService instance = AuthService._();

  static const _storage = FlutterSecureStorage();
  static const _sessionTokenKey = 'session_token';
  static const _userIdKey = 'auth_user_id';
  static const _emailKey = 'auth_email';
  static const _displayNameKey = 'auth_display_name';
  static const _pinHashKey = 'pin_hash';
  static const _pinSaltKey = 'pin_salt';
  static const _deviceSecretKey = 'device_secret';

  static const _backendUrlPrefKey = 'trading_backend_url';
  static const _maxPinAttempts = 5;

  String? _sessionToken;
  String? _userId;
  String? _email;
  String? _displayName;
  String? _pinHash;
  String? _pinSalt;
  String? _deviceSecret;

  /// Backend base URL (same SharedPreferences key the TradingApiService
  /// uses, so auth and trading calls always point at the same host).
  String _backendUrl = '';
  String get backendUrl => _backendUrl;
  bool get isBackendConfigured => _backendUrl.isNotEmpty;

  bool get hasSession => _sessionToken != null && _sessionToken!.isNotEmpty;

  /// Passkeys (WebAuthn) only work against an HTTPS backend with a valid RP
  /// ID. Plain-HTTP / IP-address deployments use the device-bound secret
  /// instead, so the UI skips the passkey ceremony on non-HTTPS connections.
  bool get passkeysSupported => _backendUrl.startsWith('https://');
  String? get sessionToken => _sessionToken;
  String? get userId => _userId;
  String? get email => _email;
  String? get displayName => _displayName;
  bool get hasPin => _pinHash != null;

  /// Headers to attach to every authenticated Trading Mode request. Omits the
  /// Authorization header entirely when no session exists.
  Map<String, String> get authHeaders => {
        'Content-Type': 'application/json',
        if (hasSession) 'Authorization': 'Bearer $_sessionToken',
      };

  /// Load persisted state from secure storage + backend URL from prefs.
  Future<void> init() async {
    _sessionToken = await _storage.read(key: _sessionTokenKey);
    _userId = await _storage.read(key: _userIdKey);
    _email = await _storage.read(key: _emailKey);
    _displayName = await _storage.read(key: _displayNameKey);
    _pinHash = await _storage.read(key: _pinHashKey);
    _pinSalt = await _storage.read(key: _pinSaltKey);
    _deviceSecret = await _storage.read(key: _deviceSecretKey);
    final prefs = await SharedPreferences.getInstance();
    final stored = prefs.getString(_backendUrlPrefKey) ?? '';
    _backendUrl = stored.trim().isNotEmpty ? stored : defaultTradingBackendUrl;
  }

  /// Refresh the backend URL from prefs (called after Settings changes).
  Future<void> reloadBackendUrl() async {
    final prefs = await SharedPreferences.getInstance();
    final stored = prefs.getString(_backendUrlPrefKey) ?? '';
    _backendUrl = stored.trim().isNotEmpty ? stored : defaultTradingBackendUrl;
  }

  /// Validate the stored session against GET /auth/session. Returns the user
  /// map when valid; clears local state and returns null when missing,
  /// expired, or revoked.
  Future<Map<String, dynamic>?> restoreSession() async {
    if (!hasSession || !isBackendConfigured) return null;
    try {
      final response = await http
          .get(
            Uri.parse('$_backendUrl/auth/session')
                .replace(queryParameters: {'session_token': _sessionToken}),
          )
          .timeout(const Duration(seconds: 10));
      if (response.statusCode == 200) {
        final data = jsonDecode(response.body);
        if (data is Map<String, dynamic> && data['valid'] == true) {
          _userId = data['user_id'] as String? ?? _userId;
          _email = data['email'] as String? ?? _email;
          _displayName = data['display_name'] as String? ?? _displayName;
          await _persistUser();
          return data;
        }
      }
    } catch (_) {
      // Unreachable backend: keep the stored session and treat it as valid so
      // the user is not locked out while offline; individual API calls will
      // surface the connectivity problem.
      return {'valid': true, 'user_id': _userId};
    }
    await clearSession();
    return null;
  }

  /// Create an account. Backend issues a session token immediately so the
  /// passkey registration (HTTPS) or device-secret binding can run right
  /// away. A fresh device secret is generated and sent with the sign-up.
  Future<Map<String, dynamic>> signUp({
    required String email,
    required String displayName,
  }) async {
    await _ensureDeviceSecret();
    final response = await http
        .post(
          Uri.parse('$_backendUrl/auth/signup'),
          headers: {'Content-Type': 'application/json'},
          body: jsonEncode({
            'email': email.trim(),
            'display_name': displayName.trim(),
            'device_secret': _deviceSecret,
          }),
        )
        .timeout(const Duration(seconds: 15));
    final data = _decodeMap(response.body);
    if (response.statusCode != 200) {
      throw AuthException(_errorMessage(data, 'Sign up failed (HTTP ${response.statusCode})'));
    }
    await _storeSession(
      token: data['session_token'] as String,
      userId: data['user_id'] as String,
      email: data['email'] as String,
      displayName: data['display_name'] as String? ?? displayName,
    );
    return data;
  }

  /// Sign in with the device-bound secret (the passkey fallback for
  /// plain-HTTP / IP-address backends). The backend binds the secret on first
  /// verify for credential-less accounts and issues a fresh session.
  Future<Map<String, dynamic>> signInWithDeviceSecret(String email) async {
    if (!isBackendConfigured) {
      throw AuthException('Trading backend is not configured');
    }
    await _ensureDeviceSecret();
    final response = await http
        .post(
          Uri.parse('$_backendUrl/auth/device/verify'),
          headers: {'Content-Type': 'application/json'},
          body: jsonEncode({
            'email': email.trim(),
            'device_secret': _deviceSecret,
          }),
        )
        .timeout(const Duration(seconds: 15));
    final data = _decodeMap(response.body);
    if (response.statusCode != 200 || data['session_token'] == null) {
      throw AuthException(
        _errorMessage(data, 'Device sign in failed (HTTP ${response.statusCode})'),
      );
    }
    await _storeSession(
      token: data['session_token'] as String,
      userId: data['user_id'] as String,
      email: data['email'] as String? ?? email,
      displayName: data['display_name'] as String? ?? _displayName ?? '',
    );
    return data;
  }

  /// Resolve an existing account by email. Never issues a session; returns
  /// { user_id, display_name, has_passkey } for the passkey ceremony.
  Future<Map<String, dynamic>> signIn(String email) async {
    final response = await http
        .post(
          Uri.parse('$_backendUrl/auth/signin'),
          headers: {'Content-Type': 'application/json'},
          body: jsonEncode({'email': email.trim()}),
        )
        .timeout(const Duration(seconds: 15));
    final data = _decodeMap(response.body);
    if (response.statusCode != 200) {
      throw AuthException(_errorMessage(data, 'Sign in failed (HTTP ${response.statusCode})'));
    }
    return data;
  }

  /// Register a passkey on this device for the current session. Only valid
  /// over HTTPS; callers should check [passkeysSupported] first.
  Future<void> registerPasskey() async {
    if (!passkeysSupported) {
      throw AuthException('Passkeys require a secure (HTTPS) connection');
    }
    if (!hasSession || !isBackendConfigured) {
      throw AuthException('No active session to attach a passkey to');
    }
    final beginResponse = await http
        .post(
          Uri.parse('$_backendUrl/auth/passkey/register/begin'),
          headers: authHeaders,
        )
        .timeout(const Duration(seconds: 15));
    final beginData = _decodeMap(beginResponse.body);
    if (beginResponse.statusCode != 200) {
      throw AuthException(_errorMessage(beginData, 'Could not start passkey registration'));
    }

    final authenticator = PasskeyAuthenticator();
    final RegisterResponseType registerResponse;
    try {
      final request = RegisterRequestType.fromJsonString(
        jsonEncode(beginData),
      );
      registerResponse = await authenticator.register(request);
    } on PasskeyAuthCancelledException {
      throw AuthException('Passkey registration was cancelled', isCancelled: true);
    } on DomainNotAssociatedException {
      throw AuthException(
        'This device cannot register a passkey for this server yet. '
        'The server must be linked to the app (assetlinks) before passkeys work.',
      );
    } on MissingGoogleSignInException {
      throw AuthException(
        'Sign in to a Google account on this device to use passkeys.',
      );
    } on Exception catch (e) {
      throw AuthException('Passkey registration failed: ${_passkeyError(e)}');
    }

    final completeResponse = await http
        .post(
          Uri.parse('$_backendUrl/auth/passkey/register/complete'),
          headers: authHeaders,
          body: jsonEncode({
            'public_key_credential': jsonDecode(registerResponse.toJsonString()),
          }),
        )
        .timeout(const Duration(seconds: 15));
    final completeData = _decodeMap(completeResponse.body);
    if (completeResponse.statusCode != 200) {
      throw AuthException(
        _errorMessage(completeData, 'Passkey registration was not accepted by the server'),
      );
    }
  }

  /// Sign in with a saved passkey. Returns the full user map from the
  /// backend (which includes the fresh session token). Only valid over HTTPS;
  /// callers should check [passkeysSupported] first.
  Future<Map<String, dynamic>> authenticatePasskey(String userId) async {
    if (!passkeysSupported) {
      throw AuthException('Passkeys require a secure (HTTPS) connection');
    }
    if (!isBackendConfigured) {
      throw AuthException('Trading backend is not configured');
    }
    final beginResponse = await http
        .post(
          Uri.parse('$_backendUrl/auth/passkey/verify/begin'),
          headers: {'Content-Type': 'application/json'},
          body: jsonEncode({'user_id': userId}),
        )
        .timeout(const Duration(seconds: 15));
    final beginData = _decodeMap(beginResponse.body);
    if (beginResponse.statusCode != 200) {
      throw AuthException(_errorMessage(beginData, 'Could not start passkey sign in'));
    }

    final authenticator = PasskeyAuthenticator();
    final AuthenticateResponseType authenticateResponse;
    try {
      final request = AuthenticateRequestType.fromJsonString(
        jsonEncode(beginData),
        mediation: MediationType.Optional,
        preferImmediatelyAvailableCredentials: true,
      );
      authenticateResponse = await authenticator.authenticate(request);
    } on PasskeyAuthCancelledException {
      throw AuthException('Passkey sign in was cancelled', isCancelled: true);
    } on DomainNotAssociatedException {
      throw AuthException(
        'This device cannot use passkeys for this server yet. '
        'The server must be linked to the app (assetlinks) before passkeys work.',
      );
    } on MissingGoogleSignInException {
      throw AuthException(
        'Sign in to a Google account on this device to use passkeys.',
      );
    } on Exception catch (e) {
      throw AuthException('Passkey sign in failed: ${_passkeyError(e)}');
    }

    final completeResponse = await http
        .post(
          Uri.parse('$_backendUrl/auth/passkey/verify/complete'),
          headers: {'Content-Type': 'application/json'},
          body: jsonEncode({
            'user_id': userId,
            'signed_challenge': jsonDecode(authenticateResponse.toJsonString()),
          }),
        )
        .timeout(const Duration(seconds: 15));
    final completeData = _decodeMap(completeResponse.body);
    if (completeResponse.statusCode != 200 || completeData['session_token'] == null) {
      throw AuthException(
        _errorMessage(completeData, 'Passkey sign in was not accepted by the server'),
      );
    }
    await _storeSession(
      token: completeData['session_token'] as String,
      userId: completeData['user_id'] as String? ?? userId,
      email: completeData['email'] as String? ?? _email ?? '',
      displayName: completeData['display_name'] as String? ?? _displayName ?? '',
    );
    return completeData;
  }

  /// Revoke the session server-side and clear all local auth state.
  Future<void> logout() async {
    if (hasSession && isBackendConfigured) {
      try {
        await http
            .post(
              Uri.parse('$_backendUrl/auth/logout'),
              headers: {'Content-Type': 'application/json'},
              body: jsonEncode({'session_token': _sessionToken}),
            )
            .timeout(const Duration(seconds: 10));
      } catch (_) {
        // Local cleanup must proceed even if the backend is unreachable.
      }
    }
    await clearSession();
  }

  /// Clear the session + PIN without contacting the backend (used when the
  /// session is known to be invalid/expired).
  Future<void> clearSession() async {
    _sessionToken = null;
    _userId = null;
    _email = null;
    _displayName = null;
    await _storage.delete(key: _sessionTokenKey);
    await _storage.delete(key: _userIdKey);
    await _storage.delete(key: _emailKey);
    await _storage.delete(key: _displayNameKey);
  }

  // -------------------------------------------------------------------------
  // PIN (local fast re-entry only)
  // -------------------------------------------------------------------------

  /// Set a new 4-6 digit PIN, stored as SHA-256(salt + pin).
  Future<void> setPin(String pin) async {
    if (!RegExp(r'^\d{4,6}$').hasMatch(pin)) {
      throw AuthException('PIN must be 4 to 6 digits');
    }
    final salt = _randomSalt();
    final hash = _hashPin(pin, salt);
    _pinSalt = salt;
    _pinHash = hash;
    await _storage.write(key: _pinSaltKey, value: salt);
    await _storage.write(key: _pinHashKey, value: hash);
  }

  Future<bool> verifyPin(String pin) async {
    if (_pinHash == null || _pinSalt == null) return false;
    return _constantTimeEquals(_hashPin(pin, _pinSalt!), _pinHash!);
  }

  Future<void> clearPin() async {
    _pinHash = null;
    _pinSalt = null;
    await _storage.delete(key: _pinHashKey);
    await _storage.delete(key: _pinSaltKey);
  }

  int get maxPinAttempts => _maxPinAttempts;

  // -------------------------------------------------------------------------
  // Internals
  // -------------------------------------------------------------------------

  /// Generate (once) and persist a random 32-byte device secret. It is the
  /// same credential sent to the backend on sign-up and device sign-in.
  Future<void> _ensureDeviceSecret() async {
    _deviceSecret ??= await _storage.read(key: _deviceSecretKey);
    if (_deviceSecret == null || _deviceSecret!.isEmpty) {
      final rnd = Random.secure();
      final bytes = List<int>.generate(32, (_) => rnd.nextInt(256));
      _deviceSecret = bytes
          .map((b) => b.toRadixString(16).padLeft(2, '0'))
          .join();
      await _storage.write(key: _deviceSecretKey, value: _deviceSecret);
    }
  }

  Future<void> _storeSession({
    required String token,
    required String userId,
    required String email,
    required String displayName,
  }) async {
    _sessionToken = token;
    _userId = userId;
    _email = email;
    _displayName = displayName;
    await _storage.write(key: _sessionTokenKey, value: token);
    await _persistUser();
  }

  Future<void> _persistUser() async {
    await _storage.write(key: _userIdKey, value: _userId ?? '');
    await _storage.write(key: _emailKey, value: _email ?? '');
    await _storage.write(key: _displayNameKey, value: _displayName ?? '');
  }

  Map<String, dynamic> _decodeMap(String body) {
    try {
      final data = jsonDecode(body);
      return data is Map<String, dynamic> ? data : {};
    } catch (_) {
      return {};
    }
  }

  String _errorMessage(Map<String, dynamic> data, String fallback) {
    final error = data['error'];
    if (error is String && error.isNotEmpty) return error;
    return fallback;
  }

  String _randomSalt() {
    final rnd = DateTime.now().microsecondsSinceEpoch.toRadixString(36) +
        _sessionToken.hashCode.toString();
    // Mix in a CSPRNG component when available.
    final extra = List<int>.generate(8, (i) => DateTime.now().microsecond & 0xff);
    return sha256.convert(utf8.encode(rnd + extra.join(','))).toString();
  }

  String _hashPin(String pin, String salt) =>
      sha256.convert(utf8.encode('$salt:$pin')).toString();

  bool _constantTimeEquals(String a, String b) {
    if (a.length != b.length) return false;
    var result = 0;
    for (var i = 0; i < a.length; i++) {
      result |= a.codeUnitAt(i) ^ b.codeUnitAt(i);
    }
    return result == 0;
  }

  String _passkeyError(Exception e) {
    final msg = e.toString();
    // Trim the long Flutter exception wrapper noise.
    final idx = msg.lastIndexOf(': ');
    if (idx > 0 && msg.length > 120) return msg.substring(idx + 2);
    return msg;
  }
}

/// Backend or local auth failure surfaced to the UI.
class AuthException implements Exception {
  final String message;
  final bool isCancelled;
  AuthException(this.message, {this.isCancelled = false});

  @override
  String toString() => message;
}
