import Foundation
import Observation
import OSLog

private func todayLogger() -> Logger {
    Logger(subsystem: "com.gabrisp.Lockty", category: "screen-time")
}

@MainActor
@Observable
final class TodayViewModel {
    private let dataProvider: TodayDataProviding
    private(set) var days: [DayKey: TodayDayState] = [:]

    init(dataProvider: TodayDataProviding) {
        self.dataProvider = dataProvider
    }

    func load(day: Date, force: Bool = false) async {
        let key = DayKey(date: day)
        if force || days[key] == nil {
            days[key] = .loading(day: day)
            todayLogger().debug("Today load started for \(key.id, privacy: .public)")
            print("Today load started for \(key.id)")
        }

        var loadedState = await dataProvider.dayState(for: day)
        days[key] = loadedState
        todayLogger().debug("Today initial state for \(key.id, privacy: .public): \(String(describing: loadedState.loadingState), privacy: .public)")
        print("Today initial state for \(key.id): \(String(describing: loadedState.loadingState))")

        guard shouldRetry(after: loadedState.loadingState) else { return }

        for attempt in 1...8 {
            try? await Task.sleep(nanoseconds: 750_000_000)
            loadedState = await dataProvider.dayState(for: day)
            days[key] = loadedState
            todayLogger().debug("Today retry \(attempt) for \(key.id, privacy: .public): \(String(describing: loadedState.loadingState), privacy: .public)")
            print("Today retry \(attempt) for \(key.id): \(String(describing: loadedState.loadingState))")

            if case .loaded = loadedState.loadingState {
                print("Today loaded successfully for \(key.id) on retry \(attempt)")
                break
            }

            guard shouldRetry(after: loadedState.loadingState) else {
                print("Today stopped retrying for \(key.id) after attempt \(attempt)")
                break
            }
        }
    }

    func state(for day: Date) -> TodayDayState {
        let key = DayKey(date: day)
        return days[key] ?? .loading(day: day)
    }

    func refresh(day: Date) async {
        await load(day: day, force: true)
    }

    func updateClassification(
        appID: AppIdentity.ID,
        classification: AppClassification,
        day: Date
    ) {
        let key = DayKey(date: day)

        Task {
            await dataProvider.updateClassification(
                appID: appID,
                classification: classification
            )
            days[key] = await dataProvider.dayState(for: day)
            print("Today classification updated for \(appID.rawValue) day=\(key.id) classification=\(classification.rawValue)")
        }
    }

    private func shouldRetry(after loadingState: TodayLoadingState) -> Bool {
        guard case .unavailable(let message) = loadingState else { return false }
        return message.localizedCaseInsensitiveContains("no screen time usage data")
            || message.localizedCaseInsensitiveContains("not available for the requested date yet")
    }
}
