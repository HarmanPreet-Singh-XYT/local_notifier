import 'dart:async';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:local_notifier/src/local_notification.dart';
import 'package:local_notifier/src/local_notification_close_reason.dart';
import 'package:local_notifier/src/local_notification_listener.dart';
import 'package:local_notifier/src/shortcut_policy.dart';

/// Represents the notification permission status on macOS
class NotificationPermissionStatus {
  const NotificationPermissionStatus({
    required this.status,
    required this.alertEnabled,
    required this.soundEnabled,
    required this.badgeEnabled,
    required this.alertStyle,
  });

  factory NotificationPermissionStatus.fromJson(Map<String, dynamic> json) {
    return NotificationPermissionStatus(
      status: json['status'] as String,
      alertEnabled: json['alertEnabled'] as bool? ?? false,
      soundEnabled: json['soundEnabled'] as bool? ?? false,
      badgeEnabled: json['badgeEnabled'] as bool? ?? false,
      alertStyle: json['alertStyle'] as String? ?? 'none',
    );
  }

  /// The authorization status: 'granted', 'denied', 'notDetermined', 'provisional', 'ephemeral', or 'unknown'
  final String status;

  /// Whether alert notifications are enabled
  final bool alertEnabled;

  /// Whether sound is enabled for notifications
  final bool soundEnabled;

  /// Whether badge is enabled for notifications
  final bool badgeEnabled;

  /// The alert style: 'none', 'banner', 'alert', or 'unknown'
  final String alertStyle;

  bool get isGranted => status == 'granted';
  bool get isDenied => status == 'denied';
  bool get isNotDetermined => status == 'notDetermined';
}

class LocalNotifier {
  LocalNotifier._() {
    _channel.setMethodCallHandler(_methodCallHandler);
  }

  /// The shared instance of [LocalNotifier].
  static final LocalNotifier instance = LocalNotifier._();

  final MethodChannel _channel = const MethodChannel('local_notifier');

  final ObserverList<LocalNotificationListener> _listeners =
      ObserverList<LocalNotificationListener>();

  bool _isInitialized = false;
  String? _appName;
  final Map<String, LocalNotification> _notifications = {};

  Future<void> _methodCallHandler(MethodCall call) async {
    String notificationId = call.arguments['notificationId'] as String;
    LocalNotification? localNotification = _notifications[notificationId];

    for (final LocalNotificationListener listener in listeners) {
      if (!_listeners.contains(listener)) {
        return;
      }

      if (call.method == 'onLocalNotificationShow') {
        listener.onLocalNotificationShow(localNotification!);
      } else if (call.method == 'onLocalNotificationClose') {
        LocalNotificationCloseReason closeReason =
            LocalNotificationCloseReason.values.firstWhere(
          (e) => e.name == call.arguments['closeReason'],
          orElse: () => LocalNotificationCloseReason.unknown,
        );
        listener.onLocalNotificationClose(
          localNotification!,
          closeReason,
        );
      } else if (call.method == 'onLocalNotificationClick') {
        listener.onLocalNotificationClick(localNotification!);
      } else if (call.method == 'onLocalNotificationClickAction') {
        int actionIndex = call.arguments['actionIndex'] as int;
        listener.onLocalNotificationClickAction(
          localNotification!,
          actionIndex,
        );
      } else {
        throw UnimplementedError();
      }
    }
  }

  List<LocalNotificationListener> get listeners {
    final List<LocalNotificationListener> localListeners =
        List<LocalNotificationListener>.from(_listeners);
    return localListeners;
  }

  bool get hasListeners {
    return _listeners.isNotEmpty;
  }

  void addListener(LocalNotificationListener listener) {
    _listeners.add(listener);
  }

  void removeListener(LocalNotificationListener listener) {
    _listeners.remove(listener);
  }

  Future<void> setup({
    required String appName,
    ShortcutPolicy shortcutPolicy = ShortcutPolicy.requireCreate,
  }) async {
    final Map<String, dynamic> arguments = {
      'appName': appName,
      'shortcutPolicy': shortcutPolicy.name,
    };
    if (Platform.isWindows) {
      _isInitialized = await _channel.invokeMethod('setup', arguments) as bool;
    } else {
      _isInitialized = true;
    }
    _appName = appName;
  }

  /// Requests notification permission from the user (macOS only).
  ///
  /// Returns `true` if permission was granted, `false` otherwise.
  /// On platforms other than macOS, this always returns `true`.
  Future<bool> requestPermission() async {
    if (!Platform.isMacOS) {
      return true;
    }

    try {
      final bool granted =
          await _channel.invokeMethod('requestPermission') as bool;
      return granted;
    } catch (e) {
      debugPrint('Error requesting notification permission: $e');
      return false;
    }
  }

  /// Checks the current notification permission status (macOS only).
  ///
  /// Returns a [NotificationPermissionStatus] object containing detailed
  /// information about the current permission state.
  /// On platforms other than macOS, returns a granted status.
  Future<NotificationPermissionStatus> checkPermission() async {
    if (!Platform.isMacOS) {
      return const NotificationPermissionStatus(
        status: 'granted',
        alertEnabled: true,
        soundEnabled: true,
        badgeEnabled: true,
        alertStyle: 'banner',
      );
    }

    try {
      final Map<dynamic, dynamic> result = await _channel
          .invokeMethod('checkPermission') as Map<dynamic, dynamic>;

      return NotificationPermissionStatus.fromJson(
        Map<String, dynamic>.from(result),
      );
    } catch (e) {
      debugPrint('Error checking notification permission: $e');
      return const NotificationPermissionStatus(
        status: 'unknown',
        alertEnabled: false,
        soundEnabled: false,
        badgeEnabled: false,
        alertStyle: 'none',
      );
    }
  }

  /// Opens the system notification settings (macOS only).
  ///
  /// This allows users to manually configure notification permissions
  /// and preferences in System Settings.
  /// Returns `true` if settings were opened successfully, `false` otherwise.
  /// On platforms other than macOS, this does nothing and returns `false`.
  Future<bool> openNotificationSettings() async {
    if (!Platform.isMacOS) {
      return false;
    }

    try {
      final bool success =
          await _channel.invokeMethod('openNotificationSettings') as bool;
      return success;
    } catch (e) {
      debugPrint('Error opening notification settings: $e');
      return false;
    }
  }

  /// Immediately shows the notification to the user.
  Future<void> notify(LocalNotification notification) async {
    if ((Platform.isLinux || Platform.isWindows) && !_isInitialized) {
      throw Exception(
        'Not initialized, please call `localNotifier.setup` first to initialize',
      );
    }

    _notifications[notification.identifier] = notification;

    final Map<String, dynamic> arguments = notification.toJson();
    arguments['appName'] = _appName;
    await _channel.invokeMethod('notify', arguments);
  }

  /// Closes the notification immediately.
  Future<void> close(LocalNotification notification) async {
    final Map<String, dynamic> arguments = notification.toJson();
    await _channel.invokeMethod('close', arguments);
  }

  /// Destroys the notification immediately.
  Future<void> destroy(LocalNotification notification) async {
    await close(notification);
    removeListener(notification);
    _notifications.remove(notification.identifier);
  }
}

final localNotifier = LocalNotifier.instance;
