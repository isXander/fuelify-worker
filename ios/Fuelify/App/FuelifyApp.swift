import SwiftUI
import SwiftData
import FirebaseCore
import FirebaseMessaging
import UserNotifications

class AppDelegate: NSObject, UIApplicationDelegate, MessagingDelegate, UNUserNotificationCenterDelegate {
    let priceWatchService = PriceWatchService()

    func application(_ application: UIApplication,
                     didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]? = nil) -> Bool {
        FirebaseApp.configure()

        Messaging.messaging().delegate = self
        UNUserNotificationCenter.current().delegate = self

        UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .sound, .badge]) { granted, _ in
            guard granted else { return }
            DispatchQueue.main.async {
                UIApplication.shared.registerForRemoteNotifications()
            }
        }

        Task { @MainActor in
            await priceWatchService.ensureRegistered()
            await priceWatchService.fetchWatches()
        }

        return true
    }

    func application(_ application: UIApplication,
                     didRegisterForRemoteNotificationsWithDeviceToken deviceToken: Data) {
        Messaging.messaging().apnsToken = deviceToken
    }

    // MARK: - MessagingDelegate

    func messaging(_ messaging: Messaging, didReceiveRegistrationToken fcmToken: String?) {
        guard let token = fcmToken else { return }
        Task { @MainActor in
            await priceWatchService.ensureRegistered()
            await priceWatchService.registerDevice(token: token)
        }
    }

    // MARK: - Silent push handling

    func application(_ application: UIApplication,
                     didReceiveRemoteNotification userInfo: [AnyHashable: Any],
                     fetchCompletionHandler completionHandler: @escaping (UIBackgroundFetchResult) -> Void) {
        guard let type = userInfo["type"] as? String, type == "price_change" else {
            completionHandler(.noData)
            return
        }

        let stationName = userInfo["station_name"] as? String ?? "Station"
        let fuelType = userInfo["fuel_type"] as? String ?? ""
        let oldPrice = userInfo["old_price"] as? String ?? ""
        let newPrice = userInfo["new_price"] as? String ?? ""
        let stationId = userInfo["station_id"] as? String ?? ""

        let fuelLabel = FuelType(rawValue: fuelType)?.shortName ?? fuelType

        let content = UNMutableNotificationContent()
        content.title = "\(stationName) - \(fuelLabel)"

        if let oldVal = Double(oldPrice), let newVal = Double(newPrice) {
            let direction = newVal < oldVal ? "dropped" : "rose"
            content.body = "Price \(direction) from \(String(format: "%.1f", oldVal))p to \(String(format: "%.1f", newVal))p"
        } else {
            content.body = "Price changed from \(oldPrice)p to \(newPrice)p"
        }

        content.sound = .default
        content.threadIdentifier = stationId

        let request = UNNotificationRequest(
            identifier: "\(stationId)-\(fuelType)-\(Date().timeIntervalSince1970)",
            content: content,
            trigger: nil
        )

        UNUserNotificationCenter.current().add(request) { _ in
            completionHandler(.newData)
        }
    }

    // MARK: - UNUserNotificationCenterDelegate

    /// Show notifications even when the app is in the foreground.
    func userNotificationCenter(_ center: UNUserNotificationCenter,
                                willPresent notification: UNNotification,
                                withCompletionHandler completionHandler: @escaping (UNNotificationPresentationOptions) -> Void) {
        completionHandler([.banner, .sound])
    }
}

@main
struct FuelifyApp: App {
    @UIApplicationDelegateAdaptor(AppDelegate.self) var delegate

    let modelContainer: ModelContainer
    @State private var preferences: UserPreferences?

    init() {
        do {
            let schema = Schema(versionedSchema: UserPreferencesSchemaV2.self)
            let config = ModelConfiguration(schema: schema)
            self.modelContainer = try ModelContainer(
                for: schema,
                migrationPlan: UserPreferencesMigrationPlan.self,
                configurations: [config]
            )
        } catch {
            fatalError("Failed to create ModelContainer: \(error)")
        }
    }

    var body: some Scene {
        WindowGroup {
            Group {
                if let preferences {
                    ContentView(preferences: preferences)
                } else {
                    ProgressView()
                }
            }
            .environment(delegate.priceWatchService)
            .task {
                if preferences == nil {
                    preferences = UserPreferences.resolve(in: modelContainer.mainContext)
                }
            }
        }
        .modelContainer(modelContainer)
    }
}
