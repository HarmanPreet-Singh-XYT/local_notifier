# macOS Notification Permission Support

This implementation adds full notification permission support for macOS to the `local_notifier` package.

## Changes Made

### 1. Updated `local_notifier.dart`

Added three new methods to the `LocalNotifier` class:

#### `requestPermission()`
Requests notification permission from the user on macOS. Shows the system permission dialog.

```dart
Future<bool> requestPermission()
```

- Returns `true` if permission was granted
- Returns `false` if permission was denied
- On non-macOS platforms, always returns `true`

#### `checkPermission()`
Checks the current notification permission status with detailed information.

```dart
Future<NotificationPermissionStatus> checkPermission()
```

Returns a `NotificationPermissionStatus` object containing:
- `status`: 'granted', 'denied', 'notDetermined', 'provisional', 'ephemeral', or 'unknown'
- `alertEnabled`: Whether alert notifications are enabled
- `soundEnabled`: Whether sound is enabled
- `badgeEnabled`: Whether badge is enabled
- `alertStyle`: 'none', 'banner', 'alert', or 'unknown'

Convenience getters:
- `isGranted`: Returns true if status is 'granted'
- `isDenied`: Returns true if status is 'denied'
- `isNotDetermined`: Returns true if status is 'notDetermined'

#### `openNotificationSettings()`
Opens the macOS System Settings > Notifications panel.

```dart
Future<bool> openNotificationSettings()
```

- Returns `true` if settings were opened successfully
- Returns `false` on failure or non-macOS platforms
- Allows users to manually configure notification preferences

### 2. New Class: `NotificationPermissionStatus`

A data class that represents the detailed permission status on macOS.

```dart
class NotificationPermissionStatus {
  final String status;
  final bool alertEnabled;
  final bool soundEnabled;
  final bool badgeEnabled;
  final String alertStyle;
  
  bool get isGranted;
  bool get isDenied;
  bool get isNotDetermined;
}
```

## Usage

### Basic Permission Flow

```dart
// 1. Check current permission status
final status = await localNotifier.checkPermission();

if (status.isNotDetermined) {
  // 2. Request permission if not yet determined
  final granted = await localNotifier.requestPermission();
  
  if (!granted) {
    print('Permission denied');
    return;
  }
}

if (status.isDenied) {
  // 3. Direct user to settings if permission was previously denied
  await localNotifier.openNotificationSettings();
  return;
}

// 4. Show notification if permission is granted
final notification = LocalNotification(
  title: 'Hello',
  body: 'This is a notification!',
);
await notification.show();
```

### Detailed Permission Check

```dart
final status = await localNotifier.checkPermission();

print('Status: ${status.status}');
print('Alerts enabled: ${status.alertEnabled}');
print('Sound enabled: ${status.soundEnabled}');
print('Badge enabled: ${status.badgeEnabled}');
print('Alert style: ${status.alertStyle}');
```

### Handling Permission Denial

```dart
Future<void> showNotificationWithPermissionCheck() async {
  final status = await localNotifier.checkPermission();
  
  if (!status.isGranted) {
    // Show dialog to user
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: Text('Enable Notifications'),
        content: Text('Please enable notifications in System Settings'),
        actions: [
          TextButton(
            onPressed: () async {
              Navigator.pop(context);
              await localNotifier.openNotificationSettings();
            },
            child: Text('Open Settings'),
          ),
        ],
      ),
    );
    return;
  }
  
  // Permission granted, show notification
  await notification.show();
}
```

## Platform Differences

### macOS
- Requires explicit permission from the user
- Permission can be: granted, denied, or not determined
- User can change permissions in System Settings at any time
- All three new methods are fully functional

### Windows & Linux
- No permission system required
- `requestPermission()` always returns `true`
- `checkPermission()` returns a default "granted" status
- `openNotificationSettings()` returns `false` (not applicable)

## Swift Implementation Details

The Swift code in `LocalNotifierPlugin.swift` handles:

1. **Permission Request**: Uses `UNUserNotificationCenter.requestAuthorization()`
2. **Permission Check**: Queries `UNNotificationSettings` for detailed status
3. **Settings Navigation**: Opens System Settings using URL schemes
4. **Auto-request**: Automatically requests permission when showing notification if status is `notDetermined`
5. **Proper Error Handling**: Returns Flutter errors for denied permissions

## Best Practices

1. **Check Before Show**: Always check permission status before attempting to show notifications
2. **Handle Denial Gracefully**: Provide clear UI to guide users to settings if permission is denied
3. **Don't Spam Requests**: Only request permission when the user takes an action that requires notifications
4. **Inform Users**: Explain why your app needs notification permission before requesting it
5. **Platform Awareness**: Use `Platform.isMacOS` checks when implementing macOS-specific UI flows

## Error Handling

The Swift implementation throws Flutter errors in these cases:

- **PERMISSION_ERROR**: Error occurred while requesting permission
- **PERMISSION_DENIED**: Notification attempted when permission is denied
- **OPEN_SETTINGS_ERROR**: Could not open System Preferences

Example error handling:

```dart
try {
  await notification.show();
} on PlatformException catch (e) {
  if (e.code == 'PERMISSION_DENIED') {
    // Handle permission denial
    print('Permission denied: ${e.message}');
    await localNotifier.openNotificationSettings();
  } else {
    print('Error: ${e.message}');
  }
}
```

## Testing

To test the implementation:

1. First run: Permission should be "notDetermined"
2. Request permission: System dialog should appear
3. Grant permission: Notifications should work
4. Deny permission: Error should be thrown when trying to show notification
5. Open settings: System Settings should open to Notifications panel
6. Change permission in settings: Check should reflect new status

## Migration Guide

If you're updating from the old version:

**Before:**
```dart
// Notifications just worked on macOS without permission
await notification.show();
```

**After:**
```dart
// Check and request permission first
final status = await localNotifier.checkPermission();
if (!status.isGranted) {
  await localNotifier.requestPermission();
}
await notification.show();
```

## Notes

- The Swift code automatically requests permission if status is `notDetermined` when showing a notification
- However, it's better practice to explicitly request permission at an appropriate time in your app's UX
- Notification settings are per-app and persist across app launches
- Users can change notification settings at any time in System Settings