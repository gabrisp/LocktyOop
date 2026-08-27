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
        }

        var loadedState = await dataProvider.dayState(for: day)
        days[key] = loadedState
        todayLogger().debug("Today initial state for \(key.id, privacy: .public): \(String(describing: loadedState.loadingState), privacy: .public)")

        guard case .unavailable = loadedState.loadingState else { return }

        for attempt in 1...20 {
            try? await Task.sleep(nanoseconds: 750_000_000)
            loadedState = await dataProvider.dayState(for: day)
            days[key] = loadedState
            todayLogger().debug("Today retry \(attempt) for \(key.id, privacy: .public): \(String(describing: loadedState.loadingState), privacy: .public)")

            if case .loaded = loadedState.loadingState {
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
        }
    }
}
