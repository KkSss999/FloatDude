import Foundation

struct AppSettings: Sendable, Equatable {
    var baseURL: URL?
    var model: String
    var hotkeyDescription: String

    static let `default` = AppSettings(
        baseURL: nil,
        model: "",
        hotkeyDescription: "Option-Space"
    )
}

@MainActor
protocol SettingsStoring: AnyObject {
    var current: AppSettings { get }
    func save(_ settings: AppSettings)
}
