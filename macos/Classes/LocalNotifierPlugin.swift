// Add this to your macos/Runner/AppDelegate.swift

import Cocoa
import FlutterMacOS
import UserNotifications

@NSApplicationMain
class AppDelegate: FlutterAppDelegate, UNUserNotificationCenterDelegate {
    override func applicationDidFinishLaunching(_ aNotification: Notification) {
        UNUserNotificationCenter.current().delegate = self
        requestNotificationPermission()
        
        let controller = mainFlutterWindow?.contentViewController as! FlutterViewController
        let notificationChannel = FlutterMethodChannel(
            name: "com.yourapp/notifications",
            binaryMessenger: controller.engine.binaryMessenger
        )
        
        notificationChannel.setMethodCallHandler { [weak self] (call, result) in
            guard let self = self else { return }
            
            switch call.method {
            case "showNotification":
                self.showNotification(call, result: result)
            case "closeNotification":
                self.closeNotification(call, result: result)
            default:
                result(FlutterMethodNotImplemented)
            }
        }
    }
    
    private func requestNotificationPermission() {
        UNUserNotificationCenter.current().requestAuthorization(
            options: [.alert, .sound, .badge]
        ) { granted, error in
            if let error = error {
                print("Notification permission error: \(error.localizedDescription)")
            }
        }
    }
    
    private func showNotification(_ call: FlutterMethodCall, result: @escaping FlutterResult) {
        guard let args = call.arguments as? [String: Any],
              let identifier = args["identifier"] as? String else {
            result(FlutterError(code: "INVALID_ARGS", message: nil, details: nil))
            return
        }
        
        let content = UNMutableNotificationContent()
        content.title = args["title"] as? String ?? ""
        content.subtitle = args["subtitle"] as? String ?? ""
        content.body = args["body"] as? String ?? ""
        content.sound = .default
        
        let request = UNNotificationRequest(
            identifier: identifier,
            content: content,
            trigger: nil
        )
        
        UNUserNotificationCenter.current().add(request) { error in
            if let error = error {
                result(FlutterError(code: "NOTIFICATION_ERROR", 
                                  message: error.localizedDescription, 
                                  details: nil))
            } else {
                result(true)
            }
        }
    }
    
    private func closeNotification(_ call: FlutterMethodCall, result: @escaping FlutterResult) {
        guard let args = call.arguments as? [String: Any],
              let identifier = args["identifier"] as? String else {
            result(FlutterError(code: "INVALID_ARGS", message: nil, details: nil))
            return
        }
        
        UNUserNotificationCenter.current().removeDeliveredNotifications(withIdentifiers: [identifier])
        result(true)
    }
    
    // MARK: - UNUserNotificationCenterDelegate
    
    func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        didReceive response: UNNotificationResponse,
        withCompletionHandler completionHandler: @escaping () -> Void
    ) {
        // Handle notification click
        completionHandler()
    }
    
    func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        willPresent notification: UNNotification,
        withCompletionHandler completionHandler: @escaping (UNNotificationPresentationOptions) -> Void
    ) {
        if #available(macOS 11.0, *) {
            completionHandler([.banner, .sound])
        } else {
            completionHandler([.alert, .sound])
        }
    }
}