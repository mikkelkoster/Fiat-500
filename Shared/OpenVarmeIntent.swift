import AppIntents
import Foundation

/// Opens the app on a deep link. Used by the Control Center buttons: the command itself runs in
/// the app, where the account lives, so nothing is sent from the extension.
@available(iOS 18.0, *)
struct OpenVarmeIntent: AppIntent {
    static let title: LocalizedStringResource = "Open Varme"
    static let description = IntentDescription("Opens Varme and sends the command.")
    static let openAppWhenRun = true
    static let isDiscoverable = false

    @Parameter(title: "Action")
    var link: String

    init() {}
    init(link: String) { self.link = link }

    @MainActor
    func perform() async throws -> some IntentResult & OpensIntent {
        .result(opensIntent: OpenURLIntent(URL(string: "varme://\(link)")!))
    }
}
