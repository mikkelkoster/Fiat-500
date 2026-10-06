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

struct IntentError: LocalizedError {
    let message: String
    init(_ message: String) { self.message = message }
    var errorDescription: String? { message }
}

struct PreheatShortcuts: AppShortcutsProvider {
    static var appShortcuts: [AppShortcut] {
        AppShortcut(
            intent: StartPreheatIntent(),
            phrases: ["Preheat my car with \(.applicationName)", "\(.applicationName) preheat"],
            shortTitle: "Preheat",
            systemImageName: "thermometer.sun.fill"
        )
        AppShortcut(
            intent: StopPreheatIntent(),
            phrases: ["Stop preheating with \(.applicationName)"],
            shortTitle: "Stop Preheat",
            systemImageName: "thermometer.snowflake"
        )
    }
}
