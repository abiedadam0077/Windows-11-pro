import 'package:flutter_local_notifications/flutter_local_notifications.dart';

/// Local notifications only (no push server). They are delivered while the app
/// process is alive; WinPilot does not run a permanent background service.
class NotificationService {
  final FlutterLocalNotificationsPlugin _plugin = FlutterLocalNotificationsPlugin();
  bool _ready = false;

  Future<void> init() async {
    if (_ready) return;
    try {
      const android = AndroidInitializationSettings('@mipmap/ic_launcher');
      await _plugin.initialize(const InitializationSettings(android: android));
      _ready = true;
    } catch (_) {
      _ready = false;
    }
  }

  /// Asks the user for the Android 13+ POST_NOTIFICATIONS permission.
  Future<bool> requestPermission() async {
    await init();
    final impl = _plugin.resolvePlatformSpecificImplementation<
        AndroidFlutterLocalNotificationsPlugin>();
    try {
      return await impl?.requestNotificationsPermission() ?? false;
    } catch (_) {
      return false;
    }
  }

  Future<void> show({
    required int id,
    required String title,
    required String body,
    required String channelName,
    required String channelDescription,
  }) async {
    await init();
    if (!_ready) return;
    try {
      await _plugin.show(
        id,
        title,
        body,
        NotificationDetails(
          android: AndroidNotificationDetails(
            _channelId,
            channelName,
            channelDescription: channelDescription,
            importance: Importance.high,
            priority: Priority.high,
            autoCancel: true,
          ),
        ),
      );
    } catch (_) {
      // Notifications are best-effort; never crash the session flow.
    }
  }

  static const _channelId = 'winpilot_sessions';
}
