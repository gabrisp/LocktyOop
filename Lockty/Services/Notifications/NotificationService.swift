import Foundation
import UserNotifications

enum NotificationAuthorizationState: String, Codable, Hashable {
    case notDetermined, denied, authorized, provisional, ephemeral, unavailable
}

protocol NotificationServicing {
    var authorizationState: NotificationAuthorizationState { get }
    func route(_ payload: NotificationPayload) -> PendingSystemEvent?
    func refreshAuthorization() async -> NotificationAuthorizationState
    func requestAuthorization() async -> NotificationAuthorizationState
}

struct MockNotificationService: NotificationServicing {
    var authorizationState: NotificationAuthorizationState = .notDetermined
    private let resolver = NotificationRouteResolver()

    func route(_ payload: NotificationPayload) -> PendingSystemEvent? {
        resolver.resolve(payload)
    }

    func refreshAuthorization() async -> NotificationAuthorizationState { authorizationState }
    func requestAuthorization() async -> NotificationAuthorizationState { .authorized }
}

final class LiveNotificationService: NotificationServicing {
    private let center = UNUserNotificationCenter.current()
    private(set) var authorizationState: NotificationAuthorizationState = .notDetermined

    func refreshAuthorization() async -> NotificationAuthorizationState {
        let settings = await center.notificationSettings()
        authorizationState = Self.map(settings.authorizationStatus)
        return authorizationState
    }

    func requestAuthorization() async -> NotificationAuthorizationState {
        do { _ = try await center.requestAuthorization(options: [.alert, .badge, .sound]) }
        catch { authorizationState = .denied; return authorizationState }
        return await refreshAuthorization()
    }

    func route(_ payload: NotificationPayload) -> PendingSystemEvent? {
        NotificationRouteResolver().resolve(payload)
    }

    private static func map(_ status: UNAuthorizationStatus) -> NotificationAuthorizationState {
        switch status {
        case .notDetermined: .notDetermined
        case .denied: .denied
        case .authorized: .authorized
        case .provisional: .provisional
        case .ephemeral: .ephemeral
        @unknown default: .unavailable
        }
    }
}
