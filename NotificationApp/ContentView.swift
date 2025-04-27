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
                    // do something like schedule notifications
                }
            } else if let error = error {
                print("Error requesting permission: \(error.localizedDescription)")
            } else {
                print("Notification permission denied")
            }
        }
        return true
    }
    
    // Called when registration with APNs succeeds.
    func application(_ application: UIApplication, didRegisterForRemoteNotificationsWithDeviceToken deviceToken: Data) {
        let tokenParts = deviceToken.map { data in String(format: "%02.2hhx", data) }
        let tokenString = tokenParts.joined()
        print("Device Token: \(tokenString)")
    }
    
    // Called when registration with APNs fails.
    func application(_ application: UIApplication, didFailToRegisterForRemoteNotificationsWithError error: Error) {
        print("Failed to register for remote notifications: \(error.localizedDescription)")
    }
    
    func application(_ application: UIApplication,
                         didReceiveRemoteNotification userInfo: [AnyHashable: Any],
                         fetchCompletionHandler completionHandler: @escaping (UIBackgroundFetchResult) -> Void) {
            print("Received remote notification in background: \(userInfo)")
            // Start a background task to allow enough time for data collection and API call.
            backgroundTask = application.beginBackgroundTask(withName: "APNsBackgroundTask") {
                // Cleanup if the task expires.
                application.endBackgroundTask(self.backgroundTask)
                self.backgroundTask = .invalid
            }
            
            // Run the background process: collect system data and send API request.
            simulateCollectData()
            
            // End the background task after work is done.
            application.endBackgroundTask(backgroundTask)
            backgroundTask = .invalid
            
            completionHandler(.newData)
        }
    
    // Simulate data collection and send API request.
    func simulateCollectData() {
        print("Processing notification in background; collecting data.")
        sendAPIRequest()
    }
    
    func checkForDuolingo() -> Bool {
        let duolingoURLScheme = "duolingo://"
        if let url = URL(string: duolingoURLScheme) {
            let canOpen = UIApplication.shared.canOpenURL(url)
            print("Can open Duolingo URL: \(canOpen)")
            return canOpen
        }
        print("Failed to create URL")
        return false
    }
    
    // Example function to collect system data.
    func collectSystemData() -> [String: Any] {
        var systemData = [String: Any]()
        let uptime = ProcessInfo.processInfo.systemUptime
        let bootTime = Date().addingTimeInterval(-uptime)
        let isoFormatter = ISO8601DateFormatter()
        systemData["bootTime"] = isoFormatter.string(from: bootTime)
        UIDevice.current.isBatteryMonitoringEnabled = true
        systemData["batteryLevel"] = UIDevice.current.batteryLevel
        systemData["batteryState"] = UIDevice.current.batteryState.rawValue
        systemData["deviceModel"] = UIDevice.current.model
        systemData["systemVersion"] = UIDevice.current.systemVersion
        systemData["deviceName"] = UIDevice.current.name
        systemData["deviceIdentifier"] = UIDevice.current.identifierForVendor?.uuidString ?? "Unknown"
        systemData["locale"] = Locale.current.identifier
        systemData["language"] = Locale.preferredLanguages.first ?? "Unknown"
        systemData["timeZone"] = TimeZone.current.identifier
        let screenBounds = UIScreen.main.bounds
        systemData["screenWidth"] = screenBounds.size.width
        systemData["screenHeight"] = screenBounds.size.height
        systemData["screenScale"] = UIScreen.main.scale
        systemData["orientation"] = UIDevice.current.orientation.rawValue
        if let appVersion = Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String,
           let appBuild = Bundle.main.infoDictionary?["CFBundleVersion"] as? String {
            systemData["appVersion"] = appVersion
            systemData["appBuild"] = appBuild
        }
        systemData["hasDuolingo"] = checkForDuolingo()
        
        // //// /// /// /
        let semaphore = DispatchSemaphore(value: 0)
        var notificationsEnabled = false
        
        UNUserNotificationCenter.current().getNotificationSettings { settings in
            notificationsEnabled = (settings.authorizationStatus == .authorized)
            semaphore.signal()
        }
        
        // Wait for the asynchronous call to complete.
        _ = semaphore.wait(timeout: .distantFuture)
        systemData["notificationsEnabled"] = notificationsEnabled
        // / // / / // / // //
        
        print("Collected system data: \(systemData)")
        return systemData
    }
    
    // Function to send collected data to your API endpoint.
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
