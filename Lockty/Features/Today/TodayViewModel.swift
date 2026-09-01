import Combine
import FamilyControls
import Foundation
import ManagedSettings
import OSLog
import SwiftUI

private func todayLogger() -> Logger {
    Logger(subsystem: "com.gabrisp.Lockty", category: "screen-time")
}

struct TodayRoutineCardState: Equatable, Identifiable {
    let id: UUID
    var name: String
    var icon: String?
    var detailText: String
    var phase: TodayRoutineCardPhase
}

enum TodayRoutineCardPhase: Equatable {
    case active
    case upcoming
}

/// A running routine and the apps it holds shut.
struct TodayActiveRoutineGroup: Identifiable, Equatable {
    var id: UUID { routine.routineID }
    let routine: ActiveRoutine
    let tokens: [ApplicationToken]
}

/// One scheduled run coming up this week.
struct TodayScheduledRoutine: Identifiable, Equatable {
    /// The routine plus its start, because the same routine appears once per day it runs.
    let id: String
    let routineID: UUID
    var name: String
    var icon: String?
    var startsAt: Date
    var dayText: String
    var timeText: String
}

@MainActor
final class TodayViewModel: ObservableObject {
    private let dataProvider: TodayDataProviding
    private let routineEngine: RoutineEngine
    private let pauseEngine: PauseEngine
    private let routineRepository: RoutineRepository
    private let selectionStore: ScreenTimeSelectionStore
    private let autoFocusManager: AutoFocusManager
    private let toastCenter: LocktyToastCenter
    /// The productivity score the last load reported, so a rise can be noticed. Nil until
    /// there has been a load to compare against -- the first score of a session is not a
    /// rise, it is just the score.
    private var lastAnnouncedScore: Int?
    @Published private(set) var days: [DayKey: TodayDayState] = [:]
    @Published private(set) var dismissedPerspectiveIDsByDay: [DayKey: Set<String>] = [:]
    @Published private(set) var routineCardState: TodayRoutineCardState?
    /// Every scheduled start between now and a week out, in order.
    @Published private(set) var upcomingRoutines: [TodayScheduledRoutine] = []
    /// Whether a break can be taken at all right now.
    ///
    /// Published rather than asked for on tap: the app badges are coloured by it, so it
    /// has to be known before anything is touched.
    @Published private(set) var breakAvailability: BreakAvailability = .available

    init(
        dataProvider: TodayDataProviding,
        routineEngine: RoutineEngine,
        pauseEngine: PauseEngine,
        routineRepository: RoutineRepository,
        selectionStore: ScreenTimeSelectionStore,
        autoFocusManager: AutoFocusManager,
        toastCenter: LocktyToastCenter
    ) {
        self.dataProvider = dataProvider
        self.routineEngine = routineEngine
        self.pauseEngine = pauseEngine
        self.routineRepository = routineRepository
        self.selectionStore = selectionStore
        self.autoFocusManager = autoFocusManager
        self.toastCenter = toastCenter
    }

    /// Announces a productivity score that has gone up since the last time we looked.
    ///
    /// Only upwards, and only for today. A score falling is not news worth interrupting
    /// someone with, and a score for a day being browsed in the past has not "risen" at
    /// all -- it is simply a different day's number.
    func announceScoreIfRisen(day: Date) {
        guard Calendar.current.isDateInToday(day) else { return }
        guard case .loaded = state(for: day).loadingState else { return }
        guard let metric = state(for: day).primaryMetrics.metrics
            .first(where: { $0.kind == .productivity })
        else { return }

        let score = Int(metric.value.rounded())
        defer { lastAnnouncedScore = score }

        guard let previous = lastAnnouncedScore, score > previous else { return }
        toastCenter.show(.scoreRose(to: score, from: previous))
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
        activeRoutineGroups.flatMap(\.tokens)
    }

    /// Each running routine with the apps it is holding, in the order they started.
    ///
    /// Grouped rather than merged into one list: two routines running at once are two
    /// separate reasons a set of apps is shut, and a single undivided row would claim
    /// they were one.
    var activeRoutineGroups: [TodayActiveRoutineGroup] {
        routineEngine.activeRoutines
            .sorted { $0.startedAt < $1.startedAt }
            .map { routine in
                let selection = (try? selectionStore.load(scope: .routine(routine.routineID)))?
                    .applicationTokens ?? []
                return TodayActiveRoutineGroup(
                    routine: routine,
                    tokens: selection.stablePrefix(selection.count)
                )
            }
    }

    func load(day: Date, force: Bool = false) async {
        await refreshRoutineCard()
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

        await refreshRoutineCard()
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
            await autoFocusManager.updateMembership(for: appID, classification: classification)
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

    /// The single gate into the friction flow.
    ///
    /// Both ways in come through here: the request card the shield puts on Today, and
    /// tapping a blocked app on the routine card. They used to disagree -- the request
    /// card asked the break policy and the app badges did not -- so the same cooldown
    /// stopped one and let the other walk an entire friction before refusing at the end,
    /// which is the flow taking work it was never going to accept.
    ///
    /// A context is passed when the request names its own routine; without one this
    /// falls back to whatever is running, which is what the badges are coloured against.
    /// How a badge should be drawn for the current break policy: green while an unlock
    /// is possible, red with a clock while a cooldown runs, red and silent once there is
    /// nothing left to grant.
    var badgeAvailability: LocktyAppLockBadge.Availability {
        switch breakAvailability {
        case .available:
            return .unlockable
        case .unavailable(let unavailable):
            guard let retryAt = unavailable.retryAt else { return .exhausted }
            return .cooldown(until: retryAt)
        }
    }

    @discardableResult
    func unlockAvailability(
        for context: PauseContext? = nil,
        appID: AppIdentity.ID? = nil
    ) async -> BreakAvailability {
        // An app can be held by more than one running routine, and then every one of them
        // has to agree before it comes out -- so the app is asked about, not a routine.
        // Letting the first routine's answer stand would appear to unlock an app the
        // second one is still blocking, and the shield would go straight back up.
        if let appID = appID ?? context?.appID {
            let availability = await routineEngine.breakAvailability(
                forApp: appID,
                trigger: .manual,
                requiresFriction: true
            )
            breakAvailability = availability
            return availability
        }

        guard let routineID = context?.activeRoutineID ?? routineEngine.activeRoutine()?.routineID else {
            breakAvailability = .available
            return .available
        }

        let availability = await routineEngine.breakAvailability(
            for: routineID,
            trigger: .manual,
            requiresFriction: true
        )
        breakAvailability = availability
        return availability
    }

    private func shouldRetry(after loadingState: TodayLoadingState) -> Bool {
        guard case .unavailable(let message) = loadingState else { return false }
        return message.localizedCaseInsensitiveContains("no screen time usage data")
            || message.localizedCaseInsensitiveContains("not available for the requested date yet")
    }

    private func refreshRoutineCard() async {
        await unlockAvailability()

        if let activeRoutine = routineEngine.activeRoutine() {
            routineCardState = TodayRoutineCardState(
                id: activeRoutine.routineID,
                name: activeRoutine.nameSnapshot,
                icon: activeRoutine.iconSnapshot,
                detailText: "Activa ahora",
                phase: .active
            )
            return
        }

        let routines = (try? await routineRepository.routines()) ?? []
        let now = Date()
        upcomingRoutines = makeUpcomingRoutines(from: routines, now: now)
        let nextRoutine = routines.compactMap { routine -> (Routine, Date, TimeZone)? in
            let nextStarts = routine.triggers.compactMap { trigger -> (Date, TimeZone)? in
                guard case .schedule(let schedule) = trigger else { return nil }
                let timeZone = TimeZone(identifier: schedule.timeZoneIdentifier) ?? .current
                guard let nextStart = nextStartDate(for: schedule, from: now, timeZone: timeZone) else { return nil }
                return (nextStart, timeZone)
            }
            guard let nearest = nextStarts.min(by: { $0.0 < $1.0 }) else { return nil }
            return (routine, nearest.0, nearest.1)
        }
        .min(by: { $0.1 < $1.1 })

        routineCardState = nextRoutine.map { routine, startDate, timeZone in
            TodayRoutineCardState(
                id: routine.id,
                name: routine.name,
                icon: routine.icon,
                detailText: upcomingText(for: startDate, timeZone: timeZone),
                phase: .upcoming
            )
        }
    }

    /// Every start a scheduled routine has between now and seven days out.
    ///
    /// One entry per run, not per routine: a routine that runs Monday, Wednesday and
    /// Friday is three things coming up, and collapsing it to one line would hide two of
    /// them. Anything already running is left out -- it is not upcoming, it is on.
    private func makeUpcomingRoutines(from routines: [Routine], now: Date) -> [TodayScheduledRoutine] {
        let runningIDs = Set(routineEngine.activeRoutines.map(\.routineID))
        let horizon = now.addingTimeInterval(7 * 24 * 60 * 60)

        var entries: [TodayScheduledRoutine] = []

        for routine in routines where !runningIDs.contains(routine.id) {
            for trigger in routine.triggers {
                guard case .schedule(let schedule) = trigger, !schedule.weekdays.isEmpty else { continue }
                let timeZone = TimeZone(identifier: schedule.timeZoneIdentifier) ?? .current

                var calendar = Calendar.current
                calendar.timeZone = timeZone
                let startOfToday = calendar.startOfDay(for: now)

                for offset in 0...7 {
                    guard let day = calendar.date(byAdding: .day, value: offset, to: startOfToday) else { continue }
                    let weekdayValue = calendar.component(.weekday, from: day)
                    guard let weekday = Weekday(rawValue: weekdayValue), schedule.weekdays.contains(weekday) else {
                        continue
                    }

                    var components = calendar.dateComponents([.year, .month, .day], from: day)
                    components.hour = schedule.hour
                    components.minute = schedule.minute
                    components.second = 0

                    guard let start = calendar.date(from: components),
                          start > now,
                          start <= horizon
                    else { continue }

                    entries.append(
                        TodayScheduledRoutine(
                            id: "\(routine.id.uuidString)-\(start.timeIntervalSince1970)",
                            routineID: routine.id,
                            name: routine.name,
                            icon: routine.icon,
                            startsAt: start,
                            dayText: dayLabel(for: start, calendar: calendar),
                            timeText: timeLabel(for: start, timeZone: timeZone)
                        )
                    )
                }
            }
        }

        return entries.sorted { $0.startsAt < $1.startsAt }
    }

    private func dayLabel(for date: Date, calendar: Calendar) -> String {
        if calendar.isDateInToday(date) { return "Hoy" }
        if calendar.isDateInTomorrow(date) { return "Mañana" }

        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "es_ES")
        formatter.timeZone = calendar.timeZone
        formatter.dateFormat = "EEEE"
        return formatter.string(from: date).capitalized
    }

    private func timeLabel(for date: Date, timeZone: TimeZone) -> String {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "es_ES")
        formatter.timeZone = timeZone
        formatter.dateFormat = "HH:mm"
        return formatter.string(from: date)
    }

    private func nextStartDate(for schedule: RoutineSchedule, from reference: Date, timeZone: TimeZone) -> Date? {
        guard !schedule.weekdays.isEmpty else { return nil }

        var calendar = Calendar.current
        calendar.timeZone = timeZone
        let startOfReferenceDay = calendar.startOfDay(for: reference)

        for offset in 0...7 {
            guard let day = calendar.date(byAdding: .day, value: offset, to: startOfReferenceDay) else { continue }
            let weekdayValue = calendar.component(.weekday, from: day)
            guard let weekday = Weekday(rawValue: weekdayValue), schedule.weekdays.contains(weekday) else { continue }

            var components = calendar.dateComponents([.year, .month, .day], from: day)
            components.hour = schedule.hour
            components.minute = schedule.minute
            components.second = 0

            guard let candidate = calendar.date(from: components), candidate > reference else { continue }
            return candidate
        }

        return nil
    }

    private func upcomingText(for date: Date, timeZone: TimeZone) -> String {
        var calendar = Calendar.current
        calendar.timeZone = timeZone

        let timeFormatter = DateFormatter()
        timeFormatter.locale = Locale(identifier: "es_ES")
        timeFormatter.timeZone = timeZone
        timeFormatter.dateFormat = "HH:mm"
        let timeText = timeFormatter.string(from: date)

        if calendar.isDateInToday(date) {
            return "Empieza hoy · \(timeText)"
        }
        if calendar.isDateInTomorrow(date) {
            return "Empieza mañana · \(timeText)"
        }

        let weekdayFormatter = DateFormatter()
        weekdayFormatter.locale = Locale(identifier: "es_ES")
        weekdayFormatter.timeZone = timeZone
        weekdayFormatter.dateFormat = "EEEE"
        let weekdayText = weekdayFormatter.string(from: date)
        return "Empieza \(weekdayText) · \(timeText)"
    }
}
