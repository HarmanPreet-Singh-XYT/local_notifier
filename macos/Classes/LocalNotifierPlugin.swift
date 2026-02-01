import Cocoa
import FlutterMacOS
import UserNotifications

public class LocalNotifierPlugin: NSObject, FlutterPlugin, UNUserNotificationCenterDelegate {
    var registrar: FlutterPluginRegistrar!
    var channel: FlutterMethodChannel!
    
    public override init() {
        super.init()
        UNUserNotificationCenter.current().delegate = self
        requestNotificationPermission()
    }
    
    private func requestNotificationPermission() {
        UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .sound, .badge]) { granted, error in
            if let error = error {
                print("Notification permission error: \(error.localizedDescription)")
            }
        }
    }
    
    public static func register(with registrar: FlutterPluginRegistrar) {
        let channel = FlutterMethodChannel(name: "local_notifier", binaryMessenger: registrar.messenger)
        let instance = LocalNotifierPlugin()
        instance.registrar = registrar
        instance.channel = channel
        registrar.addMethodCallDelegate(instance, channel: channel)
    }
    
    public func handle(_ call: FlutterMethodCall, result: @escaping FlutterResult) {
        switch call.method {
        case "notify":
            notify(call, result: result)
        case "close":
            close(call, result: result)
        default:
            result(FlutterMethodNotImplemented)
        }
    }
    
    public func notify(_ call: FlutterMethodCall, result: @escaping FlutterResult) {
        let args = call.arguments as! Dictionary<String, Any>
        let identifier: String = args["identifier"] as! String
        let title: String? = args["title"] as? String
        let subtitle: String? = args["subtitle"] as? String
        let body: String? = args["body"] as? String
        
        let content = UNMutableNotificationContent()
        if let title = title {
            content.title = title
        }
        if let subtitle = subtitle {
            content.subtitle = subtitle
        }
        if let body = body {
            content.body = body
        }
        content.sound = .default
        
        // Handle actions
        let actions: [NSDictionary]? = args["actions"] as? [NSDictionary]
        if let actions = actions, !actions.isEmpty {
            let actionDict = actions.first as! [String: Any]
            let actionText: String = actionDict["text"] as? String ?? "Action"
            
            let action = UNNotificationAction(
                identifier: "\(identifier)_action",
                title: actionText,
                options: .foreground
            )
            let category = UNNotificationCategory(
                identifier: "\(identifier)_category",
                actions: [action],
                intentIdentifiers: [],
                options: []
            )
            UNUserNotificationCenter.current().setNotificationCategories([category])
            content.categoryIdentifier = "\(identifier)_category"
        }
        
        // Trigger immediately
        let request = UNNotificationRequest(
            identifier: identifier,
            content: content,
            trigger: nil // nil triggers immediately
        )
        
        UNUserNotificationCenter.current().add(request) { error in
            if let error = error {
                print("Error delivering notification: \(error.localizedDescription)")
                result(false)
            } else {
                self._invokeMethod("onLocalNotificationShow", identifier)
                result(true)
            }
        }
    }
    
    public func close(_ call: FlutterMethodCall, result: @escaping FlutterResult) {
        let args = call.arguments as! Dictionary<String, Any>
        let identifier: String = args["identifier"] as! String
        
        UNUserNotificationCenter.current().removeDeliveredNotifications(withIdentifiers: [identifier])
        UNUserNotificationCenter.current().removePendingNotificationRequests(withIdentifiers: [identifier])
        
        _invokeMethod("onLocalNotificationClose", identifier)
        result(true)
    }
    
    // MARK: - UNUserNotificationCenterDelegate
    
    public func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        didReceive response: UNNotificationResponse,
        withCompletionHandler completionHandler: @escaping () -> Void
    ) {
        let identifier = response.notification.request.identifier
        _invokeMethod("onLocalNotificationClick", identifier)
        completionHandler()
    }
    
    public func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        willPresent notification: UNNotification,
        withCompletionHandler completionHandler: @escaping (UNNotificationPresentationOptions) -> Void
    ) {
        // Show notification even when app is in foreground
        completionHandler([.banner, .sound])
    }
    
    public func _invokeMethod(_ methodName: String, _ notificationId: String) {
        let args: NSDictionary = [
            "notificationId": notificationId,
        ]
        channel.invokeMethod(methodName, arguments: args, result: nil)
    }
}