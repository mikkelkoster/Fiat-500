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

    override init() {
        super.init()
        if WCSession.isSupported() {
            WCSession.default.delegate = self
            WCSession.default.activate()
        }
    }

    func send(_ command: String) {
        guard WCSession.default.activationState == .activated else { show("Open Varme on your iPhone once.", error: true); return }
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

    func refresh() { if WCSession.default.isReachable { send("refresh") } }

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
