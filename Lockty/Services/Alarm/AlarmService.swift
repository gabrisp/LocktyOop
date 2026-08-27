import Foundation

#if canImport(AlarmKit)
import AlarmKit
#endif

protocol AlarmServicing {
    func capabilities() -> SystemCapabilities
    func authorizationState() async -> AlarmAuthorizationState
    func requestAuthorization() async -> AlarmAuthorizationState
}

enum AlarmAuthorizationState: String, Codable, Hashable {
    case notDetermined, authorized, denied, unsupported, unavailable
}

struct MockAlarmService: AlarmServicing {
    func capabilities() -> SystemCapabilities {
        .current
    }

    func authorizationState() async -> AlarmAuthorizationState { .unsupported }
    func requestAuthorization() async -> AlarmAuthorizationState { .unsupported }
}

struct LiveAlarmService: AlarmServicing {
    func capabilities() -> SystemCapabilities { .current }

    func authorizationState() async -> AlarmAuthorizationState {
        #if canImport(AlarmKit)
        if #available(iOS 26.0, *) {
            switch AlarmManager.shared.authorizationState {
            case .notDetermined: return .notDetermined
            case .authorized: return .authorized
            case .denied: return .denied
            @unknown default: return .unavailable
            }
        }
        #endif
        return .unsupported
    }

    func requestAuthorization() async -> AlarmAuthorizationState {
        #if canImport(AlarmKit)
        if #available(iOS 26.0, *) {
            do {
                switch try await AlarmManager.shared.requestAuthorization() {
                case .notDetermined: return .notDetermined
                case .authorized: return .authorized
                case .denied: return .denied
                @unknown default: return .unavailable
                }
            } catch { return .unavailable }
        }
        #endif
        return .unsupported
    }
}
