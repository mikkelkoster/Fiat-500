import SwiftUI

@main
struct FiatPreheatApp: App {
    @UIApplicationDelegateAdaptor private var appDelegate: AppDelegate

    var body: some Scene {
        WindowGroup {
            HomeView()
                .environment(CarModel.shared)
        }
    }
}

final class AppDelegate: NSObject, UIApplicationDelegate {
    func application(
        _ application: UIApplication,
        didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]? = nil
    ) -> Bool {
        // Must happen before launch finishes so background tasks and notification actions are delivered.
        ScheduleCoordinator.shared.configure()
        return true
    }
}
