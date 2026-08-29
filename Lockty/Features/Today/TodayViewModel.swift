import Combine
import FamilyControls
import Foundation
import ManagedSettings
import OSLog
import SwiftUI

private func todayLogger() -> Logger {
    Logger(subsystem: "com.gabrisp.Lockty", category: "screen-time")
}

@MainActor
final class TodayViewModel: ObservableObject {
    private let dataProvider: TodayDataProviding
    private let routineEngine: RoutineEngine
    private let pauseEngine: PauseEngine
    private let selectionStore: ScreenTimeSelectionStore
    @Published private(set) var days: [DayKey: TodayDayState] = [:]
    @Published private(set) var dismissedPerspectiveIDsByDay: [DayKey: Set<String>] = [:]

    init(
        dataProvider: TodayDataProviding,
        routineEngine: RoutineEngine,
        pauseEngine: PauseEngine,
        selectionStore: ScreenTimeSelectionStore
    ) {
        self.dataProvider = dataProvider
        self.routineEngine = routineEngine
        self.pauseEngine = pauseEngine
        self.selectionStore = selectionStore
    }

    /// Ends the running routine. Strict mode can refuse, which the engine decides.
    func stopActiveRoutine(day: Date) async {
        await routineEngine.stop()
        // The stopped routine's cards are read off the day's state, so it has to be
        // reloaded or the checklist stays on screen with nothing behind it.
        await load(day: day, force: true)
    }

    /// The allowance currently running, if any, so a released app can show its timer.
    var activePauseAllowance: ActivePauseAllowance? {
        guard case .temporarilyAllowed(let allowance) = pauseEngine.state,
              !allowance.isExpired
        else { return nil }
        return allowance
    }

    var activeRoutine: ActiveRoutine? {
        routineEngine.activeRoutine()
    }

    /// The apps the running routine is holding shut, as tokens so their real icons can
    /// be drawn. The routine's stored ids can't produce a token, only the selection can.
    var activeRoutineTokens: [ApplicationToken] {
        guard let activeRoutine else { return [] }
        let selection = (try? selectionStore.load(scope: .routine(activeRoutine.routineID)))?.applicationTokens ?? []
        return selection.stablePrefix(selection.count)
    }

    func load(day: Date, force: Bool = false) async {
        let key = DayKey(date: day)
        if force || days[key] == nil {
            withAnimation(.smooth(duration: 0.24)) {
                days[key] = .loading(day: day)
            }
            todayLogger().debug("Today load started for \(key.id, privacy: .public)")
            print("Today load started for \(key.id)")
        }

        var loadedState = await dataProvider.dayState(for: day)
        withAnimation(.smooth(duration: 0.28)) {
            days[key] = loadedState
        }
        todayLogger().debug("Today initial state for \(key.id, privacy: .public): \(String(describing: loadedState.loadingState), privacy: .public)")
        print("Today initial state for \(key.id): \(String(describing: loadedState.loadingState))")

        guard shouldRetry(after: loadedState.loadingState) else { return }

        for attempt in 1...8 {
            try? await Task.sleep(nanoseconds: 750_000_000)
            loadedState = await dataProvider.dayState(for: day)
            withAnimation(.smooth(duration: 0.28)) {
                days[key] = loadedState
            }
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

    func visiblePerspectives(for day: Date) -> [DailyPerspective] {
        let key = DayKey(date: day)
        let dismissedIDs = dismissedPerspectiveIDsByDay[key, default: []]
        let items = (days[key] ?? .loading(day: day)).perspectives
        return items.filter { !dismissedIDs.contains($0.id) }
    }

    func dismissPerspective(_ perspectiveID: String, day: Date) {
        let key = DayKey(date: day)
        _ = withAnimation(.smooth(duration: 0.3)) {
            dismissedPerspectiveIDsByDay[key, default: []].insert(perspectiveID)
        }
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
            let updated = await dataProvider.dayState(for: day)
            withAnimation(.smooth(duration: 0.28)) {
                days[key] = updated
            }
            print("Today classification updated for \(appID.rawValue) day=\(key.id) classification=\(classification.rawValue)")
        }
    }

    func toggleActiveRoutineTask(_ taskID: UUID, day: Date) async {
        await routineEngine.completeTask(taskID)

        // Patch just this checklist item rather than reloading the whole day: a full
        // reload refetches usage/pauses/routines and replaces the day state, which
        // re-renders all of Today to flip one checkbox.
        let key = DayKey(date: day)
        guard var dayState = days[key],
              var checklist = dayState.activeRoutineChecklist,
              let index = checklist.items.firstIndex(where: { $0.id == taskID })
        else { return }

        checklist.items[index].isCompleted.toggle()
        checklist.items[index].completedAtText = nil
        checklist.completedCount = checklist.items.filter(\.isCompleted).count
        dayState.activeRoutineChecklist = checklist

        withAnimation(.smooth(duration: 0.2)) {
            days[key] = dayState
        }
    }

    private func shouldRetry(after loadingState: TodayLoadingState) -> Bool {
        guard case .unavailable(let message) = loadingState else { return false }
        return message.localizedCaseInsensitiveContains("no screen time usage data")
            || message.localizedCaseInsensitiveContains("not available for the requested date yet")
    }
}
