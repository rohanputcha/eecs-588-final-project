import SwiftUI
import UserNotifications

@main
struct NotificationDataApp: App {
    @UIApplicationDelegateAdaptor(AppDelegate.self) var appDelegate

    var body: some Scene {
        WindowGroup {
            ContentView()
        }
    }
}

class AppDelegate: NSObject, UIApplicationDelegate, UNUserNotificationCenterDelegate {
    static var shared: AppDelegate?
    var backgroundTask: UIBackgroundTaskIdentifier = .invalid

    override init() {
        super.init()
        AppDelegate.shared = self
    }
    
    func application(_ application: UIApplication,
                     didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]? = nil) -> Bool {
        UNUserNotificationCenter.current().delegate = self
        application.registerForRemoteNotifications()
        UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .sound, .badge]) { granted, error in
            if granted {
                print("Notification permission granted")
                DispatchQueue.main.async {
                    self.scheduleHourlyNotifications()
                }
            } else if let error = error {
                print("Error requesting permission: \(error.localizedDescription)")
            } else {
                print("Notification permission denied")
            }
        }
        return true
    }
    
    // Silent push handling to work in the background.
    func application(_ application: UIApplication,
                     didReceiveRemoteNotification userInfo: [AnyHashable : Any],
                     fetchCompletionHandler completionHandler: @escaping (UIBackgroundFetchResult) -> Void) {
        if let aps = userInfo["aps"] as? [String: Any],
           let contentAvailable = aps["content-available"] as? Int, contentAvailable == 1 {
            print("Silent push received in background.")
            simulateCollectData()
            completionHandler(.newData)
        } else {
            completionHandler(.noData)
        }
    }
    
    // Only works when the app is in the foreground.
    func userNotificationCenter(_ center: UNUserNotificationCenter,
                                willPresent notification: UNNotification,
                                withCompletionHandler completionHandler: @escaping (UNNotificationPresentationOptions) -> Void) {
        if notification.request.identifier == "hourly_notification" {
            simulateCollectData()
        }
        completionHandler([.banner, .sound])
    }
    
    // Runs when the user interacts with the notification.
    func userNotificationCenter(_ center: UNUserNotificationCenter,
                                didReceive response: UNNotificationResponse,
                                withCompletionHandler completionHandler: @escaping () -> Void) {
        if response.notification.request.identifier == "hourly_notification" {
            simulateCollectData()
        }
        completionHandler()
    }
    
    func simulateCollectData() {
        print("Hourly notification received; collecting data.")
        sendAPIRequest()
    }
    
    func collectSystemData() -> [String: Any] {
        var systemData = [String: Any]()

        // Collect boot time (converted to ISO8601 string)
        let uptime = ProcessInfo.processInfo.systemUptime
        let bootTime = Date().addingTimeInterval(-uptime)
        let isoFormatter = ISO8601DateFormatter()
        systemData["bootTime"] = isoFormatter.string(from: bootTime)

        // Battery info
        UIDevice.current.isBatteryMonitoringEnabled = true
        systemData["batteryLevel"] = UIDevice.current.batteryLevel
        systemData["batteryState"] = UIDevice.current.batteryState.rawValue

        // Device info
        systemData["deviceModel"] = UIDevice.current.model
        systemData["systemVersion"] = UIDevice.current.systemVersion
        systemData["deviceName"] = UIDevice.current.name
        systemData["deviceIdentifier"] = UIDevice.current.identifierForVendor?.uuidString ?? "Unknown"

        // Locale & language
        systemData["locale"] = Locale.current.identifier
        systemData["language"] = Locale.preferredLanguages.first ?? "Unknown"

        // Time zone
        systemData["timeZone"] = TimeZone.current.identifier

        // Screen details
        let screenBounds = UIScreen.main.bounds
        systemData["screenWidth"] = screenBounds.size.width
        systemData["screenHeight"] = screenBounds.size.height
        systemData["screenScale"] = UIScreen.main.scale

        // Device orientation
        systemData["orientation"] = UIDevice.current.orientation.rawValue

        // App version info (if available)
        if let appVersion = Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String,
           let appBuild = Bundle.main.infoDictionary?["CFBundleVersion"] as? String {
            systemData["appVersion"] = appVersion
            systemData["appBuild"] = appBuild
        }

        print("Collected system data: \(systemData)")
        return systemData
    }

    func sendAPIRequest() {
        let jsonData = collectSystemData()
        
        guard let url = URL(string: "https://survey.freemyip.com/flask-api/device-data") else {
            print("Invalid URL")
            return
        }
        
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        
        do {
            request.httpBody = try JSONSerialization.data(withJSONObject: jsonData, options: [])
        } catch {
            print("Error serializing JSON: \(error)")
            return
        }
        
        let task = URLSession.shared.dataTask(with: request) { data, response, error in
            if let error = error {
                print("Error sending API request: \(error.localizedDescription)")
                return
            }
            if let httpResponse = response as? HTTPURLResponse {
                print("API request response code: \(httpResponse.statusCode)")
            }
            if let data = data, let responseString = String(data: data, encoding: .utf8) {
                print("Response data: \(responseString)")
            }
        }
        task.resume()
    }
    
    func scheduleHourlyNotifications() {
        let content = UNMutableNotificationContent()
        content.title = "Hourly Data Collection"
        content.body = "Time to collect system data."
        content.sound = UNNotificationSound.default

        // Create a trigger that fires every hour.
        let trigger = UNTimeIntervalNotificationTrigger(timeInterval: 60, repeats: true)

        // Use a fixed identifier so that scheduling happens only once.
        let request = UNNotificationRequest(identifier: "hourly_notification", content: content, trigger: trigger)

        UNUserNotificationCenter.current().add(request) { error in
            if let error = error {
                print("Error scheduling hourly notification: \(error.localizedDescription)")
            } else {
                print("Hourly notification scheduled successfully.")
            }
        }
    }
}

struct ContentView: View {
    @Environment(\.scenePhase) private var scenePhase
    
    var body: some View {
        VStack(spacing: 20) {
            Text("Notification & Data Collector")
                .font(.title)
                .padding()
            
            Button("Send Test Notification & Collect Data") {
                sendLocalNotification()
                DispatchQueue.main.asyncAfter(deadline: .now() + 6) {
                    if let appDelegate = AppDelegate.shared {
                        appDelegate.simulateCollectData()
                    } else {
                        print("AppDelegate is nil")
                    }
                }
            }
            .padding()
            .background(Color.blue)
            .foregroundColor(.white)
            .cornerRadius(8)
        }
    }
    
    func sendLocalNotification() {
        let content = UNMutableNotificationContent()
        content.title = "Test Notification"
        content.body = "This notification was scheduled by your app."
        content.sound = UNNotificationSound.default
        
        // Set a trigger to fire after 5 seconds.
        let trigger = UNTimeIntervalNotificationTrigger(timeInterval: 5, repeats: false)
        let request = UNNotificationRequest(identifier: "test_notification", content: content, trigger: trigger)
        
        UNUserNotificationCenter.current().add(request) { error in
            if let error = error {
                print("Error scheduling test notification: \(error.localizedDescription)")
            } else {
                print("Test notification scheduled")
            }
        }
    }
}
