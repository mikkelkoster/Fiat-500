import Foundation
import WatchConnectivity

/// The iPhone end of the watch link. The watch never holds the account: it asks the phone to
/// send a command, and the phone replies with the outcome and a fresh snapshot of the car.
final class WatchLink: NSObject, WCSessionDelegate, @unchecked Sendable {
    static let shared = WatchLink()

    func activate() {
        guard WCSession.isSupported() else { return }
        WCSession.default.delegate = self
        WCSession.default.activate()
    }

    /// Keeps the watch app and its complications current. The latest value wins; delivered in the background.
    func publish(_ snapshot: CarSnapshot) {
        guard WCSession.isSupported(), WCSession.default.activationState == .activated, WCSession.default.isPaired,
              WCSession.default.isWatchAppInstalled, let data = try? JSONEncoder().encode(snapshot) else { return }
        try? WCSession.default.updateApplicationContext(["snapshot": data])
        if WCSession.default.isComplicationEnabled, WCSession.default.remainingComplicationUserInfoTransfers > 0 {
            WCSession.default.transferCurrentComplicationUserInfo(["snapshot": data])
        }
    }

    // MARK: WCSessionDelegate

    func session(_ session: WCSession, activationDidCompleteWith activationState: WCSessionActivationState, error: Error?) {}
    func sessionDidBecomeInactive(_ session: WCSession) {}
    func sessionDidDeactivate(_ session: WCSession) { WCSession.default.activate() }

    /// `["command": "preheat" | "stop" | "lock" | "unlock" | "lights" | "refresh"]` →
    /// `["ok": Bool, "message": String, "snapshot": Data]`.
    func session(_ session: WCSession, didReceiveMessage message: [String: Any], replyHandler: @escaping ([String: Any]) -> Void) {
        let name = message["command"] as? String ?? ""
        Task { @MainActor in
            let model = CarModel.shared
            var ok = true
            var text = ""
            if !model.hasAccount {
                ok = false; text = "Sign in on your iPhone first."
            } else if name == "refresh" {
                await model.refreshStatus()
            } else if let command = Self.commands[name] {
                let state = await model.perform(command, waitForCar: false)
                switch state {
                case .failed(let error): ok = false; text = error
                case .done(_, .failed, _): ok = false; text = "The car didn't accept it."
                default: text = Self.sent[name] ?? "Sent"
                }
            } else {
                ok = false; text = "Unknown command."
            }
            model.publishSnapshot()
            var reply: [String: Any] = ["ok": ok, "message": text]
            if let snapshot = CarSnapshot.load(), let data = try? JSONEncoder().encode(snapshot) { reply["snapshot"] = data }
            replyHandler(reply)
        }
    }

    private static let commands: [String: RemoteCommand] = [
        "preheat": .preconditionOn, "stop": .preconditionOff, "lock": .lock, "unlock": .unlock, "lights": .lights,
    ]
    private static let sent: [String: String] = [
        "preheat": "Heating", "stop": "Climate off", "lock": "Locking", "unlock": "Unlocking", "lights": "Lights flashed",
    ]
}
