import FlutterMacOS
import UserNotifications

public class LocalNotifierPlugin: NSObject, FlutterPlugin, UNUserNotificationCenterDelegate {
    private var channel: FlutterMethodChannel?
    private var registrar: FlutterPluginRegistrar?
    
    public static func register(with registrar: FlutterPluginRegistrar) {
        let channel = FlutterMethodChannel(
            name: "local_notifier",
            binaryMessenger: registrar.messenger
        )
        let instance = LocalNotifierPlugin()
        instance.channel = channel
        instance.registrar = registrar
        registrar.addMethodCallDelegate(instance, channel: channel)
        
        // Set up notification center delegate
        UNUserNotificationCenter.current().delegate = instance
    }
    
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
                    print("LocalNotifier: Permission error - \(error.localizedDescription)")
                    result(FlutterError(code: "PERMISSION_ERROR",
                                       message: error.localizedDescription,
                                       details: nil))
                } else {
                    print("LocalNotifier: Permission granted - \(granted)")
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
                case .authorized:
                    status = "granted"
                case .denied:
                    status = "denied"
                case .notDetermined:
                    status = "notDetermined"
                case .provisional:
                    status = "provisional"
                case .ephemeral:
                    status = "ephemeral"
                @unknown default:
                    status = "unknown"
                }
                
                // Also return detailed settings
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
        case .none:
            return "none"
        case .banner:
            return "banner"
        case .alert:
            return "alert"
        @unknown default:
            return "unknown"
        }
    }
    
    private func handleOpenNotificationSettings(result: @escaping FlutterResult) {
        // Open System Preferences > Notifications
        if let url = URL(string: "x-apple.systempreferences:com.apple.preference.notifications") {
            NSWorkspace.shared.open(url)
            result(true)
        } else {
            // Fallback: open System Preferences
            if let url = URL(string: "x-apple.systempreferences:") {
                NSWorkspace.shared.open(url)
                result(true)
            } else {
                result(FlutterError(code: "OPEN_SETTINGS_ERROR",
                                   message: "Could not open System Preferences",
                                   details: nil))
            }
        }
    }
    
    // MARK: - Setup
    
    private func handleSetup(_ call: FlutterMethodCall, result: @escaping FlutterResult) {
        // macOS doesn't need special setup like Windows
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
        
        // First check permission
        UNUserNotificationCenter.current().getNotificationSettings { [weak self] settings in
            DispatchQueue.main.async {
                guard let self = self else { return }
                
                if settings.authorizationStatus == .denied {
                    result(FlutterError(code: "PERMISSION_DENIED",
                                       message: "Notification permission denied. Please enable in System Settings.",
                                       details: nil))
                    return
                }
                
                if settings.authorizationStatus == .notDetermined {
                    // Request permission first
                    UNUserNotificationCenter.current().requestAuthorization(
                        options: [.alert, .sound, .badge]
                    ) { granted, error in
                        DispatchQueue.main.async {
                            if granted {
                                self.showNotification(args: args, identifier: identifier, result: result)
                            } else {
                                result(FlutterError(code: "PERMISSION_DENIED",
                                                   message: "Notification permission not granted",
                                                   details: nil))
                            }
                        }
                    }
                    return
                }
                
                // Permission granted, show notification
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
        
        // Handle actions if provided
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
            trigger: nil // Show immediately
        )
        
        UNUserNotificationCenter.current().add(request) { [weak self] error in
            DispatchQueue.main.async {
                if let error = error {
                    print("LocalNotifier: Error showing notification - \(error.localizedDescription)")
                    result(FlutterError(code: "NOTIFICATION_ERROR",
                                      message: error.localizedDescription,
                                      details: nil))
                } else {
                    print("LocalNotifier: Notification shown - \(identifier)")
                    // Notify Dart that notification was shown
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
        
        // Notify Dart that notification was closed
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
        // Show notification even when app is in foreground
        if #available(macOS 11.0, *) {
            completionHandler([.banner, .sound, .badge])
        } else {
            completionHandler([.alert, .sound, .badge])
        }
    }
}