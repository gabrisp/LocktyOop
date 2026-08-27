import Foundation
import CoreLocation

enum LocationAuthorizationState: String, Codable, Hashable {
    case notDetermined, restricted, denied, whenInUse, always, unavailable
}

protocol LocationTriggerServicing {
    var authorizationState: LocationAuthorizationState { get }
    func refreshAuthorization() async -> LocationAuthorizationState
    func requestAuthorization() async -> LocationAuthorizationState
    func startMonitoring(_ trigger: LocationTrigger) async throws
    func stopMonitoring(_ trigger: LocationTrigger) async throws
}

@MainActor
final class LiveLocationTriggerService: NSObject, CLLocationManagerDelegate, LocationTriggerServicing {
    private let manager = CLLocationManager()
    private(set) var authorizationState: LocationAuthorizationState = .notDetermined

    override init() {
        super.init()
        manager.delegate = self
        authorizationState = Self.map(manager.authorizationStatus)
    }

    func refreshAuthorization() async -> LocationAuthorizationState {
        authorizationState = Self.map(manager.authorizationStatus)
        return authorizationState
    }

    func requestAuthorization() async -> LocationAuthorizationState {
        manager.requestWhenInUseAuthorization()
        return await refreshAuthorization()
    }

    func startMonitoring(_ trigger: LocationTrigger) async throws {
        guard CLLocationManager.isMonitoringAvailable(for: CLCircularRegion.self) else { throw LocationTriggerError.unavailable }
        let region = CLCircularRegion(center: CLLocationCoordinate2D(latitude: trigger.latitude, longitude: trigger.longitude), radius: min(trigger.radiusMeters, manager.maximumRegionMonitoringDistance), identifier: trigger.id.uuidString)
        region.notifyOnEntry = trigger.startsOnEntry
        region.notifyOnExit = !trigger.startsOnEntry
        manager.startMonitoring(for: region)
    }

    func stopMonitoring(_ trigger: LocationTrigger) async throws {
        for region in manager.monitoredRegions where region.identifier == trigger.id.uuidString { manager.stopMonitoring(for: region) }
    }

    func locationManagerDidChangeAuthorization(_ manager: CLLocationManager) {
        authorizationState = Self.map(manager.authorizationStatus)
    }

    private static func map(_ status: CLAuthorizationStatus) -> LocationAuthorizationState {
        switch status {
        case .notDetermined: .notDetermined
        case .restricted: .restricted
        case .denied: .denied
        case .authorizedWhenInUse: .whenInUse
        case .authorizedAlways: .always
        @unknown default: .unavailable
        }
    }
}

enum LocationTriggerError: LocalizedError {
    case unavailable
    var errorDescription: String? { "Location region monitoring is unavailable." }
}
