import AppIntents

/// Exposed to Siri, Spotlight and Shortcuts. A Shortcuts "Time of Day" automation set to
/// "Run Immediately" running this intent is the most reliable way to preheat on a schedule.
struct StartPreheatIntent: AppIntent {
    static let title: LocalizedStringResource = "Preheat Car"
    static let description = IntentDescription("Starts climate preconditioning on your Fiat 500e.")

    @MainActor
    func perform() async throws -> some IntentResult & ProvidesDialog {
        let model = CarModel.shared
        let state = await model.startPreheat(waitForCar: false)
        if case .failed(let message) = state {
            throw IntentError(message)
        }
        return .result(dialog: "Preheating \(model.plate).")
    }
}

struct StopPreheatIntent: AppIntent {
    static let title: LocalizedStringResource = "Stop Preheating Car"
    static let description = IntentDescription("Stops climate preconditioning on your Fiat 500e.")

    @MainActor
    func perform() async throws -> some IntentResult & ProvidesDialog {
        let model = CarModel.shared
        let state = await model.stopPreheat(waitForCar: false)
        if case .failed(let message) = state {
            throw IntentError(message)
        }
        return .result(dialog: "Stopping climate on \(model.plate).")
    }
}

struct LockCarIntent: AppIntent {
    static let title: LocalizedStringResource = "Lock Car"
    static let description = IntentDescription("Locks the doors of your Fiat 500e.")

    @MainActor
    func perform() async throws -> some IntentResult & ProvidesDialog {
        let model = CarModel.shared
        if case .failed(let message) = await model.perform(.lock, waitForCar: false) {
            throw IntentError(message)
        }
        return .result(dialog: "Locking \(model.plate).")
    }
}

struct UnlockCarIntent: AppIntent {
    static let title: LocalizedStringResource = "Unlock Car"
    static let description = IntentDescription("Unlocks the doors of your Fiat 500e.")
    /// Never from a locked phone.
    static let authenticationPolicy: IntentAuthenticationPolicy = .requiresAuthentication

    @MainActor
    func perform() async throws -> some IntentResult & ProvidesDialog {
        let model = CarModel.shared
        if #available(iOS 18.0, *) {
            try await requestConfirmation(conditions: [], actionName: .go, dialog: "Unlock \(model.plate)?")
        } else {
            try await requestConfirmation(result: .result(dialog: "Unlock \(model.plate)?"))
        }
        if case .failed(let message) = await model.perform(.unlock, waitForCar: false) {
            throw IntentError(message)
        }
        return .result(dialog: "Unlocking \(model.plate).")
    }
}

struct FlashLightsIntent: AppIntent {
    static let title: LocalizedStringResource = "Turn On Car Lights"
    static let description = IntentDescription("Turns on the lights of your Fiat 500e for a moment, to spot it.")

    @MainActor
    func perform() async throws -> some IntentResult & ProvidesDialog {
        let model = CarModel.shared
        if case .failed(let message) = await model.perform(.lights, waitForCar: false) {
            throw IntentError(message)
        }
        return .result(dialog: "Turning on the lights of \(model.plate).")
    }
}

struct IntentError: LocalizedError {
    let message: String
    init(_ message: String) { self.message = message }
    var errorDescription: String? { message }
}

struct PreheatShortcuts: AppShortcutsProvider {
    static var appShortcuts: [AppShortcut] {
        AppShortcut(
            intent: StartPreheatIntent(),
            phrases: ["Preheat my car with \(.applicationName)", "\(.applicationName) preheat", "Warm up my car with \(.applicationName)"],
            shortTitle: "Preheat",
            systemImageName: "thermometer.sun.fill"
        )
        AppShortcut(
            intent: StopPreheatIntent(),
            phrases: ["Stop preheating with \(.applicationName)"],
            shortTitle: "Stop Preheat",
            systemImageName: "thermometer.snowflake"
        )
        AppShortcut(
            intent: LockCarIntent(),
            phrases: ["Lock my car with \(.applicationName)", "\(.applicationName) lock"],
            shortTitle: "Lock",
            systemImageName: "lock.fill"
        )
        AppShortcut(
            intent: UnlockCarIntent(),
            phrases: ["Unlock my car with \(.applicationName)", "\(.applicationName) unlock"],
            shortTitle: "Unlock",
            systemImageName: "lock.open.fill"
        )
        AppShortcut(
            intent: FlashLightsIntent(),
            phrases: ["Flash my car's lights with \(.applicationName)"],
            shortTitle: "Lights",
            systemImageName: "lightbulb.fill"
        )
    }
}
