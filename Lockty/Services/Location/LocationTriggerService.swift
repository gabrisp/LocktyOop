import Foundation
import CoreLocation

enum LocationAuthorizationState: String, Codable, Hashable {
    case notDetermined, restricted, denied, whenInUse, always, unavailable
}

protocol LocationTriggerServicing {
    var authorizationState: LocationAuthorizationState { get }
    func refreshAuthorization() async -> LocationAuthorizationState
    func requestAuthorization() async -> LocationAuthorizationState
    func currentLocation() async throws -> CLLocation
    func isInside(_ trigger: LocationTrigger) async throws -> Bool
    func startMonitoring(_ trigger: LocationTrigger) async throws
    func stopMonitoring(_ trigger: LocationTrigger) async throws
}

@MainActor
final class LiveLocationTriggerService: NSObject, CLLocationManagerDelegate, LocationTriggerServicing {
    private let manager = CLLocationManager()
    private(set) var authorizationState: LocationAuthorizationState = .notDetermined
    private var authorizationContinuation: CheckedContinuation<LocationAuthorizationState, Never>?
    private var locationContinuation: CheckedContinuation<CLLocation, Error>?

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
        let current = await refreshAuthorization()
        switch current {
        case .whenInUse, .always, .denied, .restricted, .unavailable:
            return current
        case .notDetermined:
            return await withCheckedContinuation { continuation in
                authorizationContinuation = continuation
                manager.requestWhenInUseAuthorization()
            }
        }
    }

    func currentLocation() async throws -> CLLocation {
        let state = await refreshAuthorization()

        switch state {
        case .notDetermined:
            let updated = await requestAuthorization()
            guard updated == .whenInUse || updated == .always else {
                throw LocationTriggerError.denied
            }
        case .denied, .restricted, .unavailable:
            throw LocationTriggerError.denied
        case .whenInUse, .always:
            break
        }

        return try await withCheckedThrowingContinuation { continuation in
            locationContinuation = continuation
            manager.requestLocation()
        }
    }

    func isInside(_ trigger: LocationTrigger) async throws -> Bool {
        let location = try await currentLocation()
        let target = CLLocation(latitude: trigger.latitude, longitude: trigger.longitude)
        return location.distance(from: target) <= trigger.radiusMeters
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
        authorizationContinuation?.resume(returning: authorizationState)
        authorizationContinuation = nil
    }

    func locationManager(_ manager: CLLocationManager, didUpdateLocations locations: [CLLocation]) {
        guard let location = locations.last else {
            locationContinuation?.resume(throwing: LocationTriggerError.noLocation)
            locationContinuation = nil
            return
        }

        locationContinuation?.resume(returning: location)
        locationContinuation = nil
    }

    func locationManager(_ manager: CLLocationManager, didFailWithError error: Error) {
        locationContinuation?.resume(throwing: error)
        locationContinuation = nil
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
    case denied
    case noLocation

    var errorDescription: String? {
        switch self {
        case .unavailable:
            "Location region monitoring is unavailable."
        case .denied:
            "Location access is required to check this friction."
        case .noLocation:
            "Lockty could not determine the current location."
        }
    }
}
