import Foundation
import HealthKit

/// Whether Lockty has asked for Health data yet.
///
/// Deliberately not "granted" or "denied" for reading. HealthKit never reveals whether a
/// read request was allowed -- that is the point of its privacy model, since knowing you
/// were refused is itself information about the person. A refused read simply returns no
/// samples, which is indistinguishable from a day with no steps. So the only honest
/// states are "not asked yet" and "asked".
nonisolated enum HealthAuthorizationState: String, Hashable {
    case unavailable
    case notRequested
    case requested

    var title: String {
        switch self {
        case .unavailable:
            "Not available on this device"
        case .notRequested:
            "Not connected"
        case .requested:
            "Connected"
        }
    }
}

protocol HealthServicing {
    var isAvailable: Bool { get }
    func authorizationState() -> HealthAuthorizationState
    /// Puts up the Health sheet. Returns once the person has answered it, whatever they
    /// answered -- see `HealthAuthorizationState` for why that cannot be reported.
    func requestAuthorization() async throws -> HealthAuthorizationState
    /// Steps taken since midnight, in the device's own calendar.
    func stepCountToday() async throws -> Int
}

enum HealthServiceError: LocalizedError {
    case unavailable
    case queryFailed(String)

    var errorDescription: String? {
        switch self {
        case .unavailable:
            "Health data is not available on this device."
        case .queryFailed(let message):
            message
        }
    }
}

final class LiveHealthService: HealthServicing {
    private let store = HKHealthStore()
    private let defaults: UserDefaults

    /// Whether the Health sheet has been put up. Stored because HealthKit will not tell
    /// us, and asking again every launch would be its own kind of nagging.
    private static let hasRequestedKey = "health.hasRequestedAuthorization"

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
    }

    private var stepType: HKQuantityType {
        HKQuantityType(.stepCount)
    }

    var isAvailable: Bool {
        HKHealthStore.isHealthDataAvailable()
    }

    func authorizationState() -> HealthAuthorizationState {
        guard isAvailable else { return .unavailable }
        return defaults.bool(forKey: Self.hasRequestedKey) ? .requested : .notRequested
    }

    func requestAuthorization() async throws -> HealthAuthorizationState {
        guard isAvailable else { throw HealthServiceError.unavailable }

        try await store.requestAuthorization(toShare: [], read: [stepType])
        defaults.set(true, forKey: Self.hasRequestedKey)
        return .requested
    }

    func stepCountToday() async throws -> Int {
        guard isAvailable else { throw HealthServiceError.unavailable }

        let calendar = Calendar.current
        let startOfDay = calendar.startOfDay(for: Date())
        let predicate = HKQuery.predicateForSamples(
            withStart: startOfDay,
            end: Date(),
            options: [.strictStartDate]
        )

        return try await withCheckedThrowingContinuation { continuation in
            let query = HKStatisticsQuery(
                quantityType: stepType,
                quantitySamplePredicate: predicate,
                // Summed, not averaged: the phone and a watch each report their own
                // samples and HealthKit already de-duplicates the overlap.
                options: .cumulativeSum
            ) { _, statistics, error in
                if let error {
                    continuation.resume(throwing: HealthServiceError.queryFailed(error.localizedDescription))
                    return
                }

                // No sum is a day with no steps -- and also what a refused read looks
                // like. Both are honestly reported as zero; there is nothing else to say.
                guard let sum = statistics?.sumQuantity() else {
                    continuation.resume(returning: 0)
                    return
                }

                continuation.resume(returning: Int(sum.doubleValue(for: .count())))
            }

            store.execute(query)
        }
    }
}
