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
        
        // Request permissions
        instance.requestNotificationPermissions()
    }
    
    private func requestNotificationPermissions() {
        UNUserNotificationCenter.current().requestAuthorization(
            options: [.alert, .sound, .badge]
        ) { granted, error in
            if let error = error {
                print("LocalNotifier: Permission error - \(error.localizedDescription)")
            } else {
                print("LocalNotifier: Permission granted - \(granted)")
            }
        }
    }
    
    public func handle(_ call: FlutterMethodCall, result: @escaping FlutterResult) {
        switch call.method {
        case "setup":
            handleSetup(call, result: result)
        case "notify":
            handleNotify(call, result: result)
        case "close":
            handleClose(call, result: result)
        default:
            result(FlutterMethodNotImplemented)
        }
    }
    
    private func handleSetup(_ call: FlutterMethodCall, result: @escaping FlutterResult) {
        // macOS doesn't need special setup like Windows
        result(true)
    }
    
    private func handleNotify(_ call: FlutterMethodCall, result: @escaping FlutterResult) {
        guard let args = call.arguments as? [String: Any],
              let identifier = args["identifier"] as? String else {
            result(FlutterError(code: "INVALID_ARGS", 
                              message: "Missing identifier", 
                              details: nil))
            return
        }
        
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
                    result(FlutterError(code: "NOTIFICATION_ERROR",
                                      message: error.localizedDescription,
                                      details: nil))
                } else {
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
            // User clicked on the notification itself
            channel?.invokeMethod("onLocalNotificationClick", arguments: [
                "notificationId": identifier
            ])
        } else if response.actionIdentifier == UNNotificationDismissActionIdentifier {
            // User dismissed the notification
            channel?.invokeMethod("onLocalNotificationClose", arguments: [
                "notificationId": identifier,
                "closeReason": "userCanceled"
            ])
        } else if response.actionIdentifier.hasPrefix("action_") {
            // User clicked an action button
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