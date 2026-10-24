import SwiftUI

@main
struct FiatPreheatApp: App {
    @UIApplicationDelegateAdaptor private var appDelegate: AppDelegate

    var body: some Scene {
        WindowGroup {
            RootView()
                .environment(CarModel.shared)
                .tint(V.text)
                .onOpenURL { CarModel.shared.handle($0) }
        }
    }
}

/// Onboarding until there is an account and the owner has been through it once, then the home screen.
struct RootView: View {
    @Environment(CarModel.self) private var model

    var body: some View {
        if model.hasAccount && model.onboarded {
            HomeScreen()
        } else {
            OnboardingFlow()
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
        WatchLink.shared.activate()
        return true
    }
}
