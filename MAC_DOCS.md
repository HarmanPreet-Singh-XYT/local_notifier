# Local Notifier macOS Documentation

## Overview

This documentation covers the complete implementation of native macOS notifications in a Flutter application, including permission handling, notification display, and user interaction callbacks.

---

## Table of Contents

1. [Architecture Overview](#architecture-overview)
2. [Installation](#installation)
3. [Native Implementation (Swift)](#native-implementation-swift)
4. [Dart Services](#dart-services)
5. [UI Components](#ui-components)
6. [API Reference](#api-reference)
7. [Usage Examples](#usage-examples)
8. [Troubleshooting](#troubleshooting)
9. [Best Practices](#best-practices)

---

## Architecture Overview

```
┌─────────────────────────────────────────────────────────────────┐
│                        Flutter App (Dart)                       │
├─────────────────────────────────────────────────────────────────┤
│  ┌─────────────────┐  ┌─────────────────┐  ┌─────────────────┐  │
│  │ LocalNotifier   │  │ Permission      │  │ UI Components   │  │
│  │ (Plugin API)    │  │ Service         │  │ (Dialogs)       │  │
│  └────────┬────────┘  └────────┬────────┘  └─────────────────┘  │
│           │                    │                                 │
│           └──────────┬─────────┘                                 │
│                      │                                           │
│           ┌──────────▼──────────┐                                │
│           │   MethodChannel     │                                │
│           │  'local_notifier'   │                                │
│           └──────────┬──────────┘                                │
└──────────────────────┼──────────────────────────────────────────┘
                       │
┌──────────────────────┼──────────────────────────────────────────┐
│                      │           macOS Native (Swift)           │
│           ┌──────────▼──────────┐                                │
│           │ LocalNotifierPlugin │                                │
│           └──────────┬──────────┘                                │
│                      │                                           │
│           ┌──────────▼──────────┐                                │
│           │ UNUserNotification  │                                │
│           │      Center         │                                │
│           └─────────────────────┘                                │
└─────────────────────────────────────────────────────────────────┘
```

### Method Channel Communication

| Direction | Method | Description |
|-----------|--------|-------------|
| Dart → Swift | `setup` | Initialize the notifier |
| Dart → Swift | `notify` | Show a notification |
| Dart → Swift | `close` | Dismiss a notification |
| Dart → Swift | `checkPermission` | Get permission status |
| Dart → Swift | `requestPermission` | Request notification permission |
| Dart → Swift | `openNotificationSettings` | Open System Preferences |
| Swift → Dart | `onLocalNotificationShow` | Notification displayed callback |
| Swift → Dart | `onLocalNotificationClick` | Notification clicked callback |
| Swift → Dart | `onLocalNotificationClose` | Notification dismissed callback |
| Swift → Dart | `onLocalNotificationClickAction` | Action button clicked callback |

---

## Installation

### Step 1: Add Dependencies

**pubspec.yaml**
```yaml
dependencies:
  flutter:
    sdk: flutter
  local_notifier: ^0.1.6
  uuid: ^4.0.0
```

### Step 2: Configure macOS

**macos/Runner/Info.plist** - Add notification description:
```xml
<key>NSUserNotificationAlertStyle</key>
<string>banner</string>
```

**macos/Runner/DebugProfile.entitlements** and **Release.entitlements**:
```xml
<key>com.apple.security.app-sandbox</key>
<true/>
```

### Step 3: Install Native Plugin

Place the `LocalNotifierPlugin.swift` file in the plugin's macOS Classes directory:

```bash
# Find plugin location
PLUGIN_PATH=$(find ~/.pub-cache/hosted/pub.dev -name "local_notifier-*" -type d | head -1)

# Create Classes directory if needed
mkdir -p "$PLUGIN_PATH/macos/Classes"

# Copy the plugin file
cp LocalNotifierPlugin.swift "$PLUGIN_PATH/macos/Classes/"
```

### Step 4: Clean and Rebuild

```bash
flutter clean
rm -rf macos/Pods macos/Podfile.lock
flutter pub get
cd macos && pod install && cd ..
flutter run -d macos
```

---

## Native Implementation (Swift)

### LocalNotifierPlugin.swift

```swift
import FlutterMacOS
import UserNotifications

public class LocalNotifierPlugin: NSObject, FlutterPlugin, UNUserNotificationCenterDelegate {
    private var channel: FlutterMethodChannel?
    private var registrar: FlutterPluginRegistrar?
    
    // MARK: - Plugin Registration
    
    public static func register(with registrar: FlutterPluginRegistrar) {
        let channel = FlutterMethodChannel(
            name: "local_notifier",
            binaryMessenger: registrar.messenger
        )
        let instance = LocalNotifierPlugin()
        instance.channel = channel
        instance.registrar = registrar
        registrar.addMethodCallDelegate(instance, channel: channel)
        
        UNUserNotificationCenter.current().delegate = instance
    }
    
    // MARK: - Method Call Handler
    
    public func handle(_ call: FlutterMethodCall, result: @escaping FlutterResult) {
        switch call.method {
        case "setup":
            handleSetup(call, result: result)
        case "notify":
            handleNotify(call, result: result)
        case "close":
            handleClose(call, result: result)
        case "requestPermission":
            handleRequestPermission(result: result)
        case "checkPermission":
            handleCheckPermission(result: result)
        case "openNotificationSettings":
            handleOpenNotificationSettings(result: result)
        default:
            result(FlutterMethodNotImplemented)
        }
    }
    
    // MARK: - Permission Handling
    
    private func handleRequestPermission(result: @escaping FlutterResult) {
        UNUserNotificationCenter.current().requestAuthorization(
            options: [.alert, .sound, .badge]
        ) { granted, error in
            DispatchQueue.main.async {
                if let error = error {
                    result(FlutterError(code: "PERMISSION_ERROR",
                                       message: error.localizedDescription,
                                       details: nil))
                } else {
                    result(granted)
                }
            }
        }
    }
    
    private func handleCheckPermission(result: @escaping FlutterResult) {
        UNUserNotificationCenter.current().getNotificationSettings { settings in
            DispatchQueue.main.async {
                let status: String
                switch settings.authorizationStatus {
                case .authorized: status = "granted"
                case .denied: status = "denied"
                case .notDetermined: status = "notDetermined"
                case .provisional: status = "provisional"
                case .ephemeral: status = "ephemeral"
                @unknown default: status = "unknown"
                }
                
                let response: [String: Any] = [
                    "status": status,
                    "alertEnabled": settings.alertSetting == .enabled,
                    "soundEnabled": settings.soundSetting == .enabled,
                    "badgeEnabled": settings.badgeSetting == .enabled,
                    "alertStyle": self.alertStyleToString(settings.alertStyle)
                ]
                
                result(response)
            }
        }
    }
    
    private func alertStyleToString(_ style: UNAlertStyle) -> String {
        switch style {
        case .none: return "none"
        case .banner: return "banner"
        case .alert: return "alert"
        @unknown default: return "unknown"
        }
    }
    
    private func handleOpenNotificationSettings(result: @escaping FlutterResult) {
        if let url = URL(string: "x-apple.systempreferences:com.apple.preference.notifications") {
            NSWorkspace.shared.open(url)
            result(true)
        } else if let url = URL(string: "x-apple.systempreferences:") {
            NSWorkspace.shared.open(url)
            result(true)
        } else {
            result(FlutterError(code: "OPEN_SETTINGS_ERROR",
                               message: "Could not open System Preferences",
                               details: nil))
        }
    }
    
    // MARK: - Setup
    
    private func handleSetup(_ call: FlutterMethodCall, result: @escaping FlutterResult) {
        result(true)
    }
    
    // MARK: - Notifications
    
    private func handleNotify(_ call: FlutterMethodCall, result: @escaping FlutterResult) {
        guard let args = call.arguments as? [String: Any],
              let identifier = args["identifier"] as? String else {
            result(FlutterError(code: "INVALID_ARGS",
                              message: "Missing identifier",
                              details: nil))
            return
        }
        
        UNUserNotificationCenter.current().getNotificationSettings { [weak self] settings in
            DispatchQueue.main.async {
                guard let self = self else { return }
                
                if settings.authorizationStatus == .denied {
                    result(FlutterError(code: "PERMISSION_DENIED",
                                       message: "Notification permission denied",
                                       details: nil))
                    return
                }
                
                if settings.authorizationStatus == .notDetermined {
                    UNUserNotificationCenter.current().requestAuthorization(
                        options: [.alert, .sound, .badge]
                    ) { granted, _ in
                        DispatchQueue.main.async {
                            if granted {
                                self.showNotification(args: args, identifier: identifier, result: result)
                            } else {
                                result(FlutterError(code: "PERMISSION_DENIED",
                                                   message: "Permission not granted",
                                                   details: nil))
                            }
                        }
                    }
                    return
                }
                
                self.showNotification(args: args, identifier: identifier, result: result)
            }
        }
    }
    
    private func showNotification(args: [String: Any], identifier: String, result: @escaping FlutterResult) {
        let content = UNMutableNotificationContent()
        content.title = args["title"] as? String ?? ""
        content.subtitle = args["subtitle"] as? String ?? ""
        content.body = args["body"] as? String ?? ""
        
        let silent = args["silent"] as? Bool ?? false
        if !silent {
            content.sound = .default
        }
        
        // Handle actions
        if let actionsData = args["actions"] as? [[String: Any]], !actionsData.isEmpty {
            var actions: [UNNotificationAction] = []
            for (index, actionData) in actionsData.enumerated() {
                if let text = actionData["text"] as? String {
                    let action = UNNotificationAction(
                        identifier: "action_\(index)",
                        title: text,
                        options: [.foreground]
                    )
                    actions.append(action)
                }
            }
            
            if !actions.isEmpty {
                let category = UNNotificationCategory(
                    identifier: "category_\(identifier)",
                    actions: actions,
                    intentIdentifiers: [],
                    options: []
                )
                UNUserNotificationCenter.current().setNotificationCategories([category])
                content.categoryIdentifier = "category_\(identifier)"
            }
        }
        
        let request = UNNotificationRequest(
            identifier: identifier,
            content: content,
            trigger: nil
        )
        
        UNUserNotificationCenter.current().add(request) { [weak self] error in
            DispatchQueue.main.async {
                if let error = error {
                    result(FlutterError(code: "NOTIFICATION_ERROR",
                                      message: error.localizedDescription,
                                      details: nil))
                } else {
                    self?.channel?.invokeMethod("onLocalNotificationShow", arguments: [
                        "notificationId": identifier
                    ])
                    result(true)
                }
            }
        }
    }
    
    private func handleClose(_ call: FlutterMethodCall, result: @escaping FlutterResult) {
        guard let args = call.arguments as? [String: Any],
              let identifier = args["identifier"] as? String else {
            result(FlutterError(code: "INVALID_ARGS",
                              message: "Missing identifier",
                              details: nil))
            return
        }
        
        UNUserNotificationCenter.current().removeDeliveredNotifications(withIdentifiers: [identifier])
        UNUserNotificationCenter.current().removePendingNotificationRequests(withIdentifiers: [identifier])
        
        channel?.invokeMethod("onLocalNotificationClose", arguments: [
            "notificationId": identifier,
            "closeReason": "userCanceled"
        ])
        
        result(true)
    }
    
    // MARK: - UNUserNotificationCenterDelegate
    
    public func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        didReceive response: UNNotificationResponse,
        withCompletionHandler completionHandler: @escaping () -> Void
    ) {
        let identifier = response.notification.request.identifier
        
        if response.actionIdentifier == UNNotificationDefaultActionIdentifier {
            channel?.invokeMethod("onLocalNotificationClick", arguments: [
                "notificationId": identifier
            ])
        } else if response.actionIdentifier == UNNotificationDismissActionIdentifier {
            channel?.invokeMethod("onLocalNotificationClose", arguments: [
                "notificationId": identifier,
                "closeReason": "userCanceled"
            ])
        } else if response.actionIdentifier.hasPrefix("action_") {
            if let indexStr = response.actionIdentifier.split(separator: "_").last,
               let index = Int(indexStr) {
                channel?.invokeMethod("onLocalNotificationClickAction", arguments: [
                    "notificationId": identifier,
                    "actionIndex": index
                ])
            }
        }
        
        completionHandler()
    }
    
    public func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        willPresent notification: UNNotification,
        withCompletionHandler completionHandler: @escaping (UNNotificationPresentationOptions) -> Void
    ) {
        if #available(macOS 11.0, *) {
            completionHandler([.banner, .sound, .badge])
        } else {
            completionHandler([.alert, .sound, .badge])
        }
    }
}
```

---

## Dart Services

### NotificationPermissionService

**lib/services/notification_permission_service.dart**

```dart
import 'dart:io';
import 'package:flutter/services.dart';

/// Represents the current notification permission status
enum NotificationPermissionStatus {
  /// User has granted permission
  granted,
  
  /// User has explicitly denied permission
  denied,
  
  /// Permission has not been requested yet
  notDetermined,
  
  /// Provisional authorization (iOS/macOS specific)
  provisional,
  
  /// Ephemeral authorization (App Clips)
  ephemeral,
  
  /// Unable to determine status
  unknown,
}

/// Detailed information about notification permissions and settings
class NotificationPermissionInfo {
  /// The authorization status
  final NotificationPermissionStatus status;
  
  /// Whether alert notifications are enabled
  final bool alertEnabled;
  
  /// Whether notification sounds are enabled
  final bool soundEnabled;
  
  /// Whether badge updates are enabled
  final bool badgeEnabled;
  
  /// The alert style: 'none', 'banner', or 'alert'
  final String alertStyle;

  NotificationPermissionInfo({
    required this.status,
    required this.alertEnabled,
    required this.soundEnabled,
    required this.badgeEnabled,
    required this.alertStyle,
  });

  /// Returns true if notifications are fully configured and will display
  bool get isFullyEnabled => 
      status == NotificationPermissionStatus.granted && 
      alertEnabled && 
      alertStyle != 'none';

  /// Returns true if user action is needed to enable notifications
  bool get needsAttention =>
      status == NotificationPermissionStatus.denied ||
      (status == NotificationPermissionStatus.granted && !alertEnabled) ||
      alertStyle == 'none';

  @override
  String toString() {
    return 'NotificationPermissionInfo('
           'status: $status, '
           'alertEnabled: $alertEnabled, '
           'soundEnabled: $soundEnabled, '
           'badgeEnabled: $badgeEnabled, '
           'alertStyle: $alertStyle)';
  }
}

/// Service for managing notification permissions on macOS
class NotificationPermissionService {
  static const MethodChannel _channel = MethodChannel('local_notifier');

  /// Check the current notification permission status
  /// 
  /// Returns detailed information about the permission state including
  /// whether alerts, sounds, and badges are enabled.
  /// 
  /// Example:
  /// ```dart
  /// final info = await NotificationPermissionService.checkPermission();
  /// if (info.needsAttention) {
  ///   // Show permission dialog
  /// }
  /// ```
  static Future<NotificationPermissionInfo> checkPermission() async {
    if (!Platform.isMacOS) {
      return NotificationPermissionInfo(
        status: NotificationPermissionStatus.granted,
        alertEnabled: true,
        soundEnabled: true,
        badgeEnabled: true,
        alertStyle: 'banner',
      );
    }

    try {
      final result = await _channel.invokeMethod('checkPermission');
      final Map<String, dynamic> response = Map<String, dynamic>.from(result);
      
      return NotificationPermissionInfo(
        status: _parseStatus(response['status'] as String),
        alertEnabled: response['alertEnabled'] as bool? ?? false,
        soundEnabled: response['soundEnabled'] as bool? ?? false,
        badgeEnabled: response['badgeEnabled'] as bool? ?? false,
        alertStyle: response['alertStyle'] as String? ?? 'unknown',
      );
    } on PlatformException catch (e) {
      print('Error checking permission: ${e.message}');
      return NotificationPermissionInfo(
        status: NotificationPermissionStatus.unknown,
        alertEnabled: false,
        soundEnabled: false,
        badgeEnabled: false,
        alertStyle: 'unknown',
      );
    }
  }

  /// Request notification permission from the user
  /// 
  /// This will display the system permission dialog if permission
  /// has not been determined yet. If permission was previously denied,
  /// this will return false and the user must enable notifications
  /// manually in System Settings.
  /// 
  /// Returns `true` if permission was granted, `false` otherwise.
  /// 
  /// Example:
  /// ```dart
  /// final granted = await NotificationPermissionService.requestPermission();
  /// if (!granted) {
  ///   // Show instructions to enable in System Settings
  /// }
  /// ```
  static Future<bool> requestPermission() async {
    if (!Platform.isMacOS) return true;

    try {
      final result = await _channel.invokeMethod('requestPermission');
      return result == true;
    } on PlatformException catch (e) {
      print('Error requesting permission: ${e.message}');
      return false;
    }
  }

  /// Open the macOS System Settings to the Notifications pane
  /// 
  /// Use this when the user needs to manually enable notifications
  /// after previously denying permission.
  /// 
  /// Returns `true` if settings were opened successfully.
  /// 
  /// Example:
  /// ```dart
  /// await NotificationPermissionService.openNotificationSettings();
  /// ```
  static Future<bool> openNotificationSettings() async {
    if (!Platform.isMacOS) return false;

    try {
      final result = await _channel.invokeMethod('openNotificationSettings');
      return result == true;
    } on PlatformException catch (e) {
      print('Error opening settings: ${e.message}');
      return false;
    }
  }

  static NotificationPermissionStatus _parseStatus(String status) {
    switch (status) {
      case 'granted':
        return NotificationPermissionStatus.granted;
      case 'denied':
        return NotificationPermissionStatus.denied;
      case 'notDetermined':
        return NotificationPermissionStatus.notDetermined;
      case 'provisional':
        return NotificationPermissionStatus.provisional;
      case 'ephemeral':
        return NotificationPermissionStatus.ephemeral;
      default:
        return NotificationPermissionStatus.unknown;
    }
  }
}
```

---

## UI Components

### NotificationPermissionDialog

**lib/widgets/notification_permission_dialog.dart**

```dart
import 'package:flutter/material.dart';
import '../services/notification_permission_service.dart';

/// A dialog that explains notification permissions and guides users
/// to enable them in System Settings.
class NotificationPermissionDialog extends StatelessWidget {
  /// The current permission information
  final NotificationPermissionInfo permissionInfo;
  
  /// Called when the user presses the settings button
  final VoidCallback? onSettingsPressed;
  
  /// Called when the user dismisses the dialog
  final VoidCallback? onDismissPressed;

  const NotificationPermissionDialog({
    super.key,
    required this.permissionInfo,
    this.onSettingsPressed,
    this.onDismissPressed,
  });

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: Row(
        children: [
          Icon(Icons.notifications_off, color: Colors.orange[700]),
          const SizedBox(width: 12),
          const Text('Notifications Disabled'),
        ],
      ),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            'To receive alerts and reminders, please enable notifications for this app.',
          ),
          const SizedBox(height: 16),
          _buildStatusInfo(context),
          const SizedBox(height: 16),
          const Text(
            'How to enable:',
            style: TextStyle(fontWeight: FontWeight.bold),
          ),
          const SizedBox(height: 8),
          const Text('1. Click "Open Settings" below'),
          const Text('2. Find this app in the list'),
          const Text('3. Enable "Allow Notifications"'),
          const Text('4. Set alert style to "Banners" or "Alerts"'),
        ],
      ),
      actions: [
        TextButton(
          onPressed: onDismissPressed ?? () => Navigator.of(context).pop(),
          child: const Text('Later'),
        ),
        ElevatedButton.icon(
          onPressed: () {
            onSettingsPressed?.call();
            NotificationPermissionService.openNotificationSettings();
          },
          icon: const Icon(Icons.settings),
          label: const Text('Open Settings'),
        ),
      ],
    );
  }

  Widget _buildStatusInfo(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: Colors.grey[100],
        borderRadius: BorderRadius.circular(8),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _buildStatusRow('Permission', _getStatusText(permissionInfo.status),
              _getStatusColor(permissionInfo.status)),
          const SizedBox(height: 4),
          _buildStatusRow('Alerts', permissionInfo.alertEnabled ? 'Enabled' : 'Disabled',
              permissionInfo.alertEnabled ? Colors.green : Colors.red),
          const SizedBox(height: 4),
          _buildStatusRow('Alert Style', permissionInfo.alertStyle.toUpperCase(),
              permissionInfo.alertStyle == 'none' ? Colors.red : Colors.green),
          const SizedBox(height: 4),
          _buildStatusRow('Sound', permissionInfo.soundEnabled ? 'Enabled' : 'Disabled',
              permissionInfo.soundEnabled ? Colors.green : Colors.orange),
        ],
      ),
    );
  }

  Widget _buildStatusRow(String label, String value, Color valueColor) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: [
        Text(label, style: const TextStyle(fontSize: 13)),
        Text(value,
            style: TextStyle(fontSize: 13, fontWeight: FontWeight.w500, color: valueColor)),
      ],
    );
  }

  String _getStatusText(NotificationPermissionStatus status) {
    switch (status) {
      case NotificationPermissionStatus.granted:
        return 'Granted';
      case NotificationPermissionStatus.denied:
        return 'Denied';
      case NotificationPermissionStatus.notDetermined:
        return 'Not Asked';
      case NotificationPermissionStatus.provisional:
        return 'Provisional';
      case NotificationPermissionStatus.ephemeral:
        return 'Ephemeral';
      case NotificationPermissionStatus.unknown:
        return 'Unknown';
    }
  }

  Color _getStatusColor(NotificationPermissionStatus status) {
    switch (status) {
      case NotificationPermissionStatus.granted:
        return Colors.green;
      case NotificationPermissionStatus.denied:
        return Colors.red;
      case NotificationPermissionStatus.notDetermined:
        return Colors.orange;
      default:
        return Colors.grey;
    }
  }
}

/// Helper function to show the notification permission dialog
/// 
/// Example:
/// ```dart
/// final info = await NotificationPermissionService.checkPermission();
/// if (info.needsAttention) {
///   await showNotificationPermissionDialog(context, permissionInfo: info);
/// }
/// ```
Future<void> showNotificationPermissionDialog(
  BuildContext context, {
  NotificationPermissionInfo? permissionInfo,
}) async {
  final info = permissionInfo ?? await NotificationPermissionService.checkPermission();
  
  if (!context.mounted) return;
  
  await showDialog(
    context: context,
    builder: (context) => NotificationPermissionDialog(
      permissionInfo: info,
      onDismissPressed: () => Navigator.of(context).pop(),
      onSettingsPressed: () => Navigator.of(context).pop(),
    ),
  );
}
```

---

## API Reference

### LocalNotification Class

```dart
class LocalNotification {
  /// Unique identifier for the notification
  String identifier;
  
  /// The title displayed prominently
  String title;
  
  /// Secondary text below the title
  String? subtitle;
  
  /// The main content body
  String? body;
  
  /// If true, notification appears without sound
  bool silent;
  
  /// Action buttons displayed with the notification
  List<LocalNotificationAction>? actions;
  
  /// Callbacks
  VoidCallback? onShow;
  ValueChanged<LocalNotificationCloseReason>? onClose;
  VoidCallback? onClick;
  ValueChanged<int>? onClickAction;
  
  /// Show this notification
  Future<void> show();
  
  /// Close/dismiss this notification
  Future<void> close();
  
  /// Close and remove all listeners
  Future<void> destroy();
}
```

### LocalNotificationAction Class

```dart
class LocalNotificationAction {
  /// The type of action (currently only 'button')
  String type;
  
  /// The label text for the action button
  String? text;
}
```

### LocalNotificationCloseReason Enum

```dart
enum LocalNotificationCloseReason {
  /// User explicitly dismissed the notification
  userCanceled,
  
  /// Notification timed out automatically
  timedOut,
  
  /// Reason could not be determined
  unknown,
}
```

### NotificationPermissionStatus Enum

```dart
enum NotificationPermissionStatus {
  granted,        // Permission granted
  denied,         // Permission explicitly denied
  notDetermined,  // Not yet requested
  provisional,    // Provisional authorization
  ephemeral,      // Ephemeral authorization
  unknown,        // Unable to determine
}
```

### NotificationPermissionInfo Class

```dart
class NotificationPermissionInfo {
  NotificationPermissionStatus status;  // Authorization status
  bool alertEnabled;                     // Alerts enabled in settings
  bool soundEnabled;                     // Sounds enabled
  bool badgeEnabled;                     // Badge updates enabled
  String alertStyle;                     // 'none', 'banner', or 'alert'
  
  bool get isFullyEnabled;  // True if notifications will display
  bool get needsAttention;  // True if user action required
}
```

---

## Usage Examples

### Basic Initialization

```dart
import 'package:local_notifier/local_notifier.dart';
import 'services/notification_permission_service.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  
  // Initialize the notifier
  await localNotifier.setup(appName: 'MyApp');
  
  // Check permission status
  final permissionInfo = await NotificationPermissionService.checkPermission();
  print('Notifications enabled: ${permissionInfo.isFullyEnabled}');
  
  runApp(const MyApp());
}
```

### Simple Notification

```dart
Future<void> showSimpleNotification() async {
  final notification = LocalNotification(
    identifier: 'simple-1',
    title: 'Hello!',
    subtitle: 'Greeting',
    body: 'This is a simple notification.',
  );
  
  await notification.show();
}
```

### Notification with Callbacks

```dart
Future<void> showNotificationWithCallbacks() async {
  final notification = LocalNotification(
    identifier: 'callback-1',
    title: 'Task Complete',
    body: 'Your download has finished.',
  );
  
  notification.onShow = () {
    print('Notification displayed');
  };
  
  notification.onClick = () {
    print('User clicked the notification');
    // Navigate to relevant screen
  };
  
  notification.onClose = (reason) {
    print('Notification closed: ${reason.name}');
  };
  
  await notification.show();
}
```

### Notification with Actions

```dart
Future<void> showNotificationWithActions() async {
  final notification = LocalNotification(
    identifier: 'timer-complete',
    title: 'Timer Finished! ⏰',
    subtitle: 'Work Session',
    body: 'Great job! Take a break.',
    actions: [
      LocalNotificationAction(text: 'Start Break'),
      LocalNotificationAction(text: 'Skip'),
      LocalNotificationAction(text: 'Dismiss'),
    ],
  );
  
  notification.onClickAction = (actionIndex) {
    switch (actionIndex) {
      case 0:
        print('Starting break...');
        startBreakTimer();
        break;
      case 1:
        print('Skipping break...');
        startNextSession();
        break;
      case 2:
        print('Dismissed');
        break;
    }
  };
  
  await notification.show();
}
```

### Silent Notification

```dart
Future<void> showSilentNotification() async {
  final notification = LocalNotification(
    identifier: 'silent-1',
    title: 'Background Sync Complete',
    body: 'Your data has been updated.',
    silent: true,  // No sound
  );
  
  await notification.show();
}
```

### Permission Handling

```dart
class NotificationManager {
  Future<bool> ensurePermission(BuildContext context) async {
    final info = await NotificationPermissionService.checkPermission();
    
    if (info.isFullyEnabled) {
      return true;
    }
    
    if (info.status == NotificationPermissionStatus.notDetermined) {
      // First time - request permission
      return await NotificationPermissionService.requestPermission();
    }
    
    // Permission denied or alerts disabled - show dialog
    if (context.mounted) {
      await showNotificationPermissionDialog(context, permissionInfo: info);
    }
    
    return false;
  }
  
  Future<void> sendNotification(BuildContext context, LocalNotification notification) async {
    final hasPermission = await ensurePermission(context);
    
    if (hasPermission) {
      await notification.show();
    }
  }
}
```

### Managing Multiple Notifications

```dart
class NotificationService {
  final Map<String, LocalNotification> _activeNotifications = {};
  
  Future<void> show(LocalNotification notification) async {
    _activeNotifications[notification.identifier] = notification;
    
    notification.onClose = (reason) {
      _activeNotifications.remove(notification.identifier);
    };
    
    await notification.show();
  }
  
  Future<void> closeAll() async {
    for (final notification in _activeNotifications.values.toList()) {
      await notification.close();
    }
    _activeNotifications.clear();
  }
  
  Future<void> close(String identifier) async {
    final notification = _activeNotifications[identifier];
    if (notification != null) {
      await notification.close();
      _activeNotifications.remove(identifier);
    }
  }
}
```

---

## Troubleshooting

### Notifications Not Appearing

| Issue | Solution |
|-------|----------|
| Permission denied | Call `openNotificationSettings()` and guide user to enable |
| Alert style is "none" | User must change to "Banners" or "Alerts" in System Settings |
| Do Not Disturb enabled | Disable Focus mode in macOS |
| App not in notification list | Run the app at least once, then check System Settings |

### Debug Checklist

```dart
Future<void> debugNotifications() async {
  final info = await NotificationPermissionService.checkPermission();
  
  print('=== Notification Debug ===');
  print('Status: ${info.status}');
  print('Alerts Enabled: ${info.alertEnabled}');
  print('Alert Style: ${info.alertStyle}');
  print('Sound Enabled: ${info.soundEnabled}');
  print('Badge Enabled: ${info.badgeEnabled}');
  print('Fully Enabled: ${info.isFullyEnabled}');
  print('Needs Attention: ${info.needsAttention}');
  print('========================');
}
```

### Common Error Codes

| Code | Meaning | Solution |
|------|---------|----------|
| `PERMISSION_DENIED` | User denied notification permission | Show permission dialog |
| `PERMISSION_ERROR` | Error requesting permission | Check system settings |
| `NOTIFICATION_ERROR` | Failed to display notification | Check notification content |
| `INVALID_ARGS` | Missing required arguments | Ensure identifier is provided |
| `OPEN_SETTINGS_ERROR` | Cannot open System Preferences | Manual navigation required |

### Build Issues

```bash
# Clean rebuild
flutter clean
rm -rf macos/Pods macos/Podfile.lock
flutter pub get
cd macos && pod deintegrate && pod install --repo-update && cd ..
flutter build macos
```

---

## Best Practices

### 1. Always Check Permission First

```dart
Future<void> safeShowNotification(LocalNotification notification) async {
  final info = await NotificationPermissionService.checkPermission();
  
  if (!info.isFullyEnabled) {
    // Handle permission issue
    return;
  }
  
  await notification.show();
}
```

### 2. Use Meaningful Identifiers

```dart
// Good - descriptive and unique
final notification = LocalNotification(
  identifier: 'timer-session-${DateTime.now().millisecondsSinceEpoch}',
  title: 'Timer Complete',
);

// Bad - generic
final notification = LocalNotification(
  identifier: 'notif1',
  title: 'Timer Complete',
);
```

### 3. Clean Up Notifications

```dart
class TimerScreen extends StatefulWidget {
  @override
  State<TimerScreen> createState() => _TimerScreenState();
}

class _TimerScreenState extends State<TimerScreen> {
  LocalNotification? _activeNotification;
  
  @override
  void dispose() {
    // Clean up notification when leaving screen
    _activeNotification?.destroy();
    super.dispose();
  }
}
```

### 4. Handle All Callbacks

```dart
final notification = LocalNotification(
  identifier: 'complete-notification',
  title: 'Task Complete',
);

notification.onShow = () {
  // Log analytics
  analytics.logNotificationShown('task-complete');
};

notification.onClick = () {
  // Navigate to relevant content
  navigator.pushNamed('/tasks');
};

notification.onClose = (reason) {
  // Clean up resources
  cleanupNotification();
};

notification.onClickAction = (index) {
  // Handle specific actions
  handleAction(index);
};
```

### 5. Graceful Degradation

```dart
Future<void> notifyUser(String title, String body) async {
  try {
    final notification = LocalNotification(
      title: title,
      body: body,
    );
    await notification.show();
  } catch (e) {
    // Fallback to in-app notification
    showInAppSnackbar(title, body);
  }
}
```

---

## File Structure

```
lib/
├── main.dart
├── services/
│   └── notification_permission_service.dart
└── widgets/
    └── notification_permission_dialog.dart

macos/
├── Runner/
│   ├── AppDelegate.swift
│   └── Info.plist
└── Podfile

~/.pub-cache/hosted/pub.dev/local_notifier-0.1.6/
└── macos/
    ├── Classes/
    │   └── LocalNotifierPlugin.swift  (custom implementation)
    └── local_notifier.podspec
```

---

## Version Compatibility

| Component | Minimum Version |
|-----------|-----------------|
| macOS | 10.14 (Mojave) |
| Flutter | 3.3.0 |
| Dart | 3.0.0 |
| Swift | 5.0 |

---

## License

This implementation is provided under the MIT License. The `local_notifier` plugin is maintained by LeanFlutter.