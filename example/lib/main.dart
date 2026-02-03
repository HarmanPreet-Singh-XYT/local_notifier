import 'package:flutter/material.dart';
import 'package:local_notifier/local_notifier.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();

  // Initialize the notifier
  await localNotifier.setup(
    appName: 'My App Name',
    shortcutPolicy: ShortcutPolicy.requireCreate,
  );

  runApp(const MyApp());
}

class MyApp extends StatelessWidget {
  const MyApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Local Notifier Example',
      theme: ThemeData(
        primarySwatch: Colors.blue,
      ),
      home: const NotificationDemo(),
    );
  }
}

class NotificationDemo extends StatefulWidget {
  const NotificationDemo({super.key});

  @override
  State<NotificationDemo> createState() => _NotificationDemoState();
}

class _NotificationDemoState extends State<NotificationDemo> {
  NotificationPermissionStatus? _permissionStatus;
  String _statusMessage = 'Check permission status';

  @override
  void initState() {
    super.initState();
    _checkPermissionOnStart();
  }

  Future<void> _checkPermissionOnStart() async {
    final status = await localNotifier.checkPermission();
    setState(() {
      _permissionStatus = status;
      _statusMessage = 'Permission: ${status.status}';
    });
  }

  Future<void> _requestPermission() async {
    final granted = await localNotifier.requestPermission();

    setState(() {
      _statusMessage = granted ? 'Permission granted!' : 'Permission denied';
    });

    // Check status again after request
    await _checkPermissionStatus();
  }

  Future<void> _checkPermissionStatus() async {
    final status = await localNotifier.checkPermission();

    setState(() {
      _permissionStatus = status;
      _statusMessage = '''
Permission Status: ${status.status}
Alert Enabled: ${status.alertEnabled}
Sound Enabled: ${status.soundEnabled}
Badge Enabled: ${status.badgeEnabled}
Alert Style: ${status.alertStyle}
''';
    });
  }

  Future<void> _openSettings() async {
    final success = await localNotifier.openNotificationSettings();

    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            success
                ? 'Opening notification settings...'
                : 'Could not open settings',
          ),
        ),
      );
    }
  }

  Future<void> _showNotification() async {
    // Check permission first
    final status = await localNotifier.checkPermission();

    if (!status.isGranted) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Please grant notification permission first'),
          ),
        );
      }
      return;
    }

    // Create and show notification
    final notification = LocalNotification(
      title: 'Test Notification',
      body: 'This is a test notification from Flutter!',
      actions: [
        LocalNotificationAction(text: 'Action 1'),
        LocalNotificationAction(text: 'Action 2'),
      ],
    );

    notification.onShow = () {
      debugPrint('Notification shown');
    };

    notification.onClick = () {
      debugPrint('Notification clicked');
    };

    notification.onClose = (reason) {
      debugPrint('Notification closed: ${reason.name}');
    };

    notification.onClickAction = (index) {
      debugPrint('Action clicked: $index');
    };

    try {
      await notification.show();
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Notification sent!')),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Error: $e')),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Local Notifier Demo'),
      ),
      body: Padding(
        padding: const EdgeInsets.all(16.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Card(
              child: Padding(
                padding: const EdgeInsets.all(16.0),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text(
                      'Permission Status',
                      style: TextStyle(
                        fontSize: 18,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                    const SizedBox(height: 8),
                    Text(_statusMessage),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 16),
            ElevatedButton.icon(
              onPressed: _checkPermissionStatus,
              icon: const Icon(Icons.info),
              label: const Text('Check Permission Status'),
            ),
            const SizedBox(height: 8),
            ElevatedButton.icon(
              onPressed: _requestPermission,
              icon: const Icon(Icons.notifications_active),
              label: const Text('Request Permission'),
            ),
            const SizedBox(height: 8),
            ElevatedButton.icon(
              onPressed: _openSettings,
              icon: const Icon(Icons.settings),
              label: const Text('Open Notification Settings'),
            ),
            const SizedBox(height: 24),
            const Divider(),
            const SizedBox(height: 24),
            ElevatedButton.icon(
              onPressed: _showNotification,
              icon: const Icon(Icons.notification_add),
              label: const Text('Show Test Notification'),
              style: ElevatedButton.styleFrom(
                padding: const EdgeInsets.all(16),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
