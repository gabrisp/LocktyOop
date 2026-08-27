import Foundation

struct AppConfiguration: Equatable {
    let appGroupIdentifier: String

    static let current = AppConfiguration(
        appGroupIdentifier: SharedKeys.appGroupIdentifier
    )
}
