import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

/// Receives `neutralpip://` deep links from the Android side.
///
/// `MainActivity` exposes the initial intent's URI via `getInitialLink` and
/// forwards later intents (`onNewIntent`) through the `onDeepLink` callback.
/// The latest link is kept in [pendingDeepLink] so it survives the splash /
/// auth / PIN gate and can be consumed once the app shell is ready.
class DeepLinkService {
  DeepLinkService._();

  static const MethodChannel _channel = MethodChannel('neutralpip/deep_link');

  /// Latest received deep link, or null when none has arrived. The shell
  /// consumes a link (sets it back to null) once it has been handled.
  static final ValueNotifier<String?> pendingDeepLink = ValueNotifier<String?>(null);

  static bool _initialized = false;

  /// Wire up the platform channel. Call once from `main()` before runApp.
  static void init() {
    if (_initialized) return;
    _initialized = true;
    _channel.setMethodCallHandler((call) async {
      if (call.method == 'onDeepLink') {
        final link = call.arguments as String?;
        if (link != null && link.isNotEmpty) {
          pendingDeepLink.value = link;
        }
      }
      return null;
    });
    _channel
        .invokeMethod<String>('getInitialLink')
        .then((link) {
          if (link != null && link.isNotEmpty) {
            pendingDeepLink.value = link;
          }
        })
        .catchError((Object _) {
          // No link on this platform / engine; not an error worth surfacing.
        });
  }
}
