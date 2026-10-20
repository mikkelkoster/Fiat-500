import SwiftUI
import WatchConnectivity
import WidgetKit

@main
struct VarmeWatchApp: App {
    @StateObject private var model = WatchModel()

    var body: some Scene {
        WindowGroup {
            WatchHome()
                .environmentObject(model)
                .onAppear { model.refresh() }
        }
    }
}

/// The watch's view of the car. It holds no account: commands go to the iPhone, which answers
/// with the result and a fresh snapshot.
@MainActor
final class WatchModel: NSObject, ObservableObject, WCSessionDelegate {
    @Published var car: CarSnapshot? = CarSnapshot.load()
    @Published var sending: String?
    @Published var message: String?
    @Published var messageIsError = false

    /// The sample car, for simulator runs and screenshots: launch with -preheatDemo
    /// (and -demoScreen preheating to open heating). Nothing is sent to the iPhone.
    static let isDemo = ProcessInfo.processInfo.arguments.contains("-preheatDemo")

    override init() {
        super.init()
        if Self.isDemo {
            let heating = UserDefaults.standard.string(forKey: "demoScreen") == "preheating"
            car = CarSnapshot(carName: UserDefaults.standard.string(forKey: "demoName") ?? "My EV", plate: "ED 35079",
                              stateOfCharge: 72, rangeKm: 187, useMiles: false, isCharging: false, isPluggedIn: true,
                              isLocked: true, preheatStartedAt: heating ? Date().addingTimeInterval(-7 * 60) : nil,
                              nextSchedule: "Wed 07:30", hasCarImage: true, updatedAt: Date())
            return
        }
        if WCSession.isSupported() {
            WCSession.default.delegate = self
            WCSession.default.activate()
        }
    }

    func send(_ command: String) {
        if Self.isDemo { pretend(command); return }
        guard WCSession.default.activationState == .activated else { show("Open Luft on your iPhone once.", error: true); return }
        sending = command
        WKInterfaceDeviceHaptic.start()
        WCSession.default.sendMessage(["command": command], replyHandler: { reply in
            Task { @MainActor in
                self.sending = nil
                if let data = reply["snapshot"] as? Data { self.apply(data) }
                let ok = reply["ok"] as? Bool ?? false
                if command != "refresh" || !ok { self.show(reply["message"] as? String ?? "", error: !ok) }
                WKInterfaceDeviceHaptic.result(ok)
            }
        }, errorHandler: { _ in
            Task { @MainActor in
                self.sending = nil
                self.show("Can't reach your iPhone.", error: true)
                WKInterfaceDeviceHaptic.result(false)
            }
        })
    }

    func refresh() { if !Self.isDemo, WCSession.default.isReachable { send("refresh") } }

    /// The sample car answers after a moment, as a real one would.
    private func pretend(_ command: String) {
        sending = command
        WKInterfaceDeviceHaptic.start()
        Task {
            try? await Task.sleep(for: .seconds(1.5))
            switch command {
            case "preheat": car?.preheatStartedAt = Date()
            case "stop": car?.preheatStartedAt = nil
            case "lock": car?.isLocked = true
            case "unlock": car?.isLocked = false
            default: break
            }
            sending = nil
            show(["preheat": "Climate on", "stop": "Climate off", "lock": "Locked", "unlock": "Unlocked", "lights": "Lights flashed"][command] ?? "Done", error: false)
            WKInterfaceDeviceHaptic.result(true)
        }
    }

    private func show(_ text: String, error: Bool) {
        guard !text.isEmpty else { return }
        message = text; messageIsError = error
        Task { try? await Task.sleep(for: .seconds(3)); if self.message == text { self.message = nil } }
    }

    private func apply(_ data: Data) {
        guard let snapshot = try? JSONDecoder().decode(CarSnapshot.self, from: data) else { return }
        car = snapshot
        snapshot.save()
        WidgetCenter.shared.reloadAllTimelines()
    }

    // MARK: WCSessionDelegate

    nonisolated func session(_ session: WCSession, activationDidCompleteWith activationState: WCSessionActivationState, error: Error?) {
        if let data = session.receivedApplicationContext["snapshot"] as? Data { Task { @MainActor in self.apply(data) } }
    }
    nonisolated func session(_ session: WCSession, didReceiveApplicationContext applicationContext: [String: Any]) {
        if let data = applicationContext["snapshot"] as? Data { Task { @MainActor in self.apply(data) } }
    }
    nonisolated func session(_ session: WCSession, didReceiveUserInfo userInfo: [String: Any] = [:]) {
        if let data = userInfo["snapshot"] as? Data { Task { @MainActor in self.apply(data) } }
    }
}

import WatchKit

/// Taps on press, success or failure at the end.
enum WKInterfaceDeviceHaptic {
    static func start() { WKInterfaceDevice.current().play(.click) }
    static func result(_ ok: Bool) { WKInterfaceDevice.current().play(ok ? .success : .failure) }
}
