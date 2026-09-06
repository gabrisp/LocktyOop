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
    /// Steps over a range, for an objective counted by the week or the month.
    func stepCount(from start: Date, to end: Date) async throws -> Int
    /// Hours actually asleep in a range.
    ///
    /// Asleep, not in bed: the two differ by the half hour spent on the phone before
    /// putting it down, which is the half hour this app is about.
    func sleepHours(from start: Date, to end: Date) async throws -> Double
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

    private var sleepType: HKCategoryType {
        HKCategoryType(.sleepAnalysis)
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

        try await store.requestAuthorization(toShare: [], read: [stepType, sleepType])
        defaults.set(true, forKey: Self.hasRequestedKey)
        return .requested
    }

    func stepCountToday() async throws -> Int {
        let calendar = Calendar.current
        return try await stepCount(from: calendar.startOfDay(for: Date()), to: Date())
    }

    func stepCount(from start: Date, to end: Date) async throws -> Int {
        guard isAvailable else { throw HealthServiceError.unavailable }

        let predicate = HKQuery.predicateForSamples(
            withStart: start,
            end: end,
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

extension LiveHealthService {
    /// Hours asleep between two dates.
    ///
    /// Summed over the samples rather than taken from a single "time asleep" figure,
    /// because there is no such figure: HealthKit records sleep as a series of stretches,
    /// each with a stage, and the ones that count as sleeping are the three below. A nap
    /// and a night are both in here, which is right -- the objective is hours of sleep,
    /// not one unbroken night.
    func sleepHours(from start: Date, to end: Date) async throws -> Double {
        guard isAvailable else { throw HealthServiceError.unavailable }

        let predicate = HKQuery.predicateForSamples(withStart: start, end: end, options: [])

        return try await withCheckedThrowingContinuation { continuation in
            let query = HKSampleQuery(
                sampleType: HKCategoryType(.sleepAnalysis),
                predicate: predicate,
                limit: HKObjectQueryNoLimit,
                sortDescriptors: nil
            ) { _, samples, error in
                if let error {
                    continuation.resume(throwing: HealthServiceError.queryFailed(error.localizedDescription))
                    return
                }

                let asleep: Set<Int> = [
                    HKCategoryValueSleepAnalysis.asleepCore.rawValue,
                    HKCategoryValueSleepAnalysis.asleepDeep.rawValue,
                    HKCategoryValueSleepAnalysis.asleepREM.rawValue,
                    HKCategoryValueSleepAnalysis.asleepUnspecified.rawValue
                ]

                let seconds = (samples as? [HKCategorySample] ?? [])
                    .filter { asleep.contains($0.value) }
                    .reduce(0.0) { $0 + $1.endDate.timeIntervalSince($1.startDate) }

                continuation.resume(returning: seconds / 3600)
            }

            store.execute(query)
        }
    }
}
