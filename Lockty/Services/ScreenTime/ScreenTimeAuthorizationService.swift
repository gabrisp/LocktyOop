import Foundation
import Observation
import FamilyControls

enum ScreenTimeAuthorizationState: String, Codable, Hashable {
    case notDetermined
    case requesting
    case authorized
    case authorizedWithDataAccess
    case denied
    case revoked
    case restricted
    case unavailable
    case entitlementMissing

    var title: String {
        switch self {
        case .notDetermined: "Not requested"
        case .requesting: "Requesting"
        case .authorized: "Authorized for blocking"
        case .authorizedWithDataAccess: "Authorized with usage data access"
        case .denied: "Denied"
        case .revoked: "Revoked"
        case .restricted: "Restricted"
        case .unavailable: "Unavailable"
        case .entitlementMissing: "Entitlement missing"
        }
    }
}

protocol ScreenTimeAuthorizationServicing {
    var currentState: ScreenTimeAuthorizationState { get }
    func refreshAuthorizationState() async -> ScreenTimeAuthorizationState
    func requestAuthorization() async -> ScreenTimeAuthorizationState
}

@MainActor
@Observable
final class LiveScreenTimeAuthorizationService: ScreenTimeAuthorizationServicing {
    private(set) var currentState: ScreenTimeAuthorizationState

    init() {
        currentState = Self.map(AuthorizationCenter.shared.authorizationStatus)
    }

    func refreshAuthorizationState() async -> ScreenTimeAuthorizationState {
        currentState = Self.map(AuthorizationCenter.shared.authorizationStatus)
        return currentState
    }

    func requestAuthorization() async -> ScreenTimeAuthorizationState {
        currentState = .requesting
        do {
            try await AuthorizationCenter.shared.requestAuthorization(for: .individual)
            currentState = Self.map(AuthorizationCenter.shared.authorizationStatus)
        } catch let error as NSError {
            currentState = error.code == 4 ? .entitlementMissing : .denied
        } catch {
            currentState = .denied
        }
        return currentState
    }

    private static func map(_ status: AuthorizationStatus) -> ScreenTimeAuthorizationState {
        if #available(iOS 26.4, *), status == .approvedWithDataAccess {
            return .authorizedWithDataAccess
        }

        switch status {
        case .notDetermined:
            return .notDetermined
        case .approved:
            return .authorized
        case .denied:
            return .denied
        default:
            return .unavailable
        }
    }
}
