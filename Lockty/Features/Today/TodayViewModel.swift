import Combine
import FamilyControls
import Foundation
import WidgetKit
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

/// A running routine, the apps it holds shut, and whether it will let any of them out.
///
/// The availability belongs to the group rather than to the card: each routine has its
/// own break policy, its own count and its own cooldown, so one answer for the whole card
/// showed a wait that belonged to one routine over apps held by another.
struct TodayActiveRoutineGroup: Identifiable, Equatable {
    var id: UUID { routine.routineID }
    let routine: ActiveRoutine
    let tokens: [ApplicationToken]
    var availability: BreakAvailability = .available
}

/// A limit that is holding its apps shut right now, and what it is holding.
///
/// The sibling of `TodayActiveRoutineGroup`. A limit that has run out is the same fact as
/// a routine that is running -- something is shut and there is a reason -- and it was the
/// only one of the two with nowhere on screen showing which apps it had taken.
struct TodayActiveLimitGroup: Identifiable, Equatable {
    var id: UUID { ruleID }
    let ruleID: UUID
    let name: String
    /// What the rule says it is, in a line: "10 opens", "2 h a day".
    let detail: String
    let tokens: [ApplicationToken]
    /// Whether this limit will open an exception, and on what terms.
    var availability: LocktyAppLockBadge.Availability
}

/// One scheduled run coming up this week.
struct TodayScheduledRoutine: Identifiable, Equatable {
    /// The routine plus its start, because the same routine appears once per day it runs.
    let id: String
    let routineID: UUID
    var name: String
    var icon: String?
    /// The routine's own colour, so its glyph on Today is the one it wears everywhere
    /// else. A column of identical grey icons says nothing about which routine is which.
    var color: RoutineColor
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
    /// Its own handle on the shared container: the limits and what they have spent live
    /// there, written by the extensions.
    private let appGroupStore = AppGroupStore()
    private let trendBuilder = DailyTrendBuilder()
    private var cancellables: Set<AnyCancellable> = []
    /// Which day the trend currently belongs to, so it is not rebuilt on every retry.
    private var trendDayKey: String?
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
    /// Rules and routines currently held, with the day the hold ends.
    @Published private(set) var pausedItems: [TodayPausedItem] = []

    /// Where every limit rule stands today. Rebuilt with the day, since the figure in it
    /// is the day's own usage.
    @Published private(set) var limits: [TodayLimitState] = []
    /// The fortnight behind the day being read, for the trend lines on the score pages.
    @Published private(set) var trend: [DailyTrendPoint] = []
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

        // The screens read this model, and this model reads the engine -- so a routine
        // that starts or ends anywhere at all lands here without anyone having to
        // remember to say so.
        //
        // Ending one from its own editor is the case that was broken: the engine stopped
        // it, the editor closed, and the Focus tab kept its ring and its card until the
        // tab was left and come back to, because only `load` refreshed them.
        routineEngine.$activeRoutines
            .map { $0.map(\.routineID) }
            .removeDuplicates()
            .dropFirst()
            .sink { [weak self] _ in
                Task { @MainActor in await self?.refreshRoutineCard() }
            }
            .store(in: &cancellables)
    }

    /// Announces a productivity score that has gone up since the last time we looked.
    ///
    /// Nothing calls this at the moment -- see the note at the Today `task` that used to.
    ///
    /// Only upwards, and only for today. A score falling is not news worth interrupting
    /// someone with, and a score for a day being browsed in the past has not "risen" at
    /// all -- it is simply a different day's number.
    func announceScoreIfRisen(day: Date) {
        guard Calendar.current.isDateInToday(day) else { return }
        guard case .loaded = state(for: day).loadingState else { return }
        guard let metric = state(for: day).primaryMetrics.metrics
            .first(where: { $0.kind == .focus })
        else { return }

        let score = Int(metric.value.rounded())
        defer { lastAnnouncedScore = score }

        guard let previous = lastAnnouncedScore, score > previous else { return }
        toastCenter.show(.scoreRose(to: score, from: previous))
    }

    /// The fortnight behind this day, read off the cached snapshots.
    ///
    /// On a background task: it is a directory of files and a decode each. Only rebuilt
    /// when the day changes -- the days behind it do not move while you are looking at
    /// them.
    private func refreshTrend(day: Date) async {
        let key = DayKey(date: day)
        guard trendDayKey != key.id else { return }
        trendDayKey = key.id

        let builder = trendBuilder
        let next = await Task.detached(priority: .utility) {
            builder.trend(endingOn: day)
        }.value

        guard trend != next else { return }
        withAnimation(.smooth(duration: 0.35)) { trend = next }
    }

    /// Leaves the day's finished scores where the home screen can read them.
    ///
    /// Only for today, and only once they are actually known: the widget has no way to
    /// compute any of this -- the figures come out of Core Data, Screen Time and half a
    /// dozen calculators -- so this is the one path by which it ever learns anything. A
    /// snapshot of a past day, or of a day still loading, would be the widget showing a
    /// screen of zeroes with confidence.
    private func writeScoreSnapshot(day: Date, state: TodayDayState) {
        guard Calendar.current.isDateInToday(day), case .loaded = state.loadingState else { return }

        let snapshot = DailyScoreSnapshot(
            day: DayKey(date: day).id,
            updatedAt: Date(),
            scores: state.primaryMetrics.metrics.map { metric in
                DailyScoreSnapshot.Score(
                    kind: metric.kind.rawValue,
                    title: metric.kind.title,
                    displayValue: metric.displayValue,
                    progress: metric.progress
                )
            },
            screenTime: state.appUsages.reduce(0) { $0 + $1.duration }
        )

        guard snapshot != appGroupStore.loadDailyScores() else { return }
        try? appGroupStore.saveDailyScores(snapshot)
        WidgetCenter.shared.reloadTimelines(ofKind: DailyScoreWidgets.kind)
    }

    /// Rereads where every limit rule stands.
    ///
    /// Only for today. A limit is a fact about now -- three opens left, twenty minutes
    /// spent -- and there is no record of what was left at four o'clock last Tuesday, so
    /// showing today's figures on a past day would be showing the wrong day's numbers
    /// under the right day's heading.
    private func refreshLimits(day: Date, state: TodayDayState, recordsOpens: Bool = true) async {
        guard Calendar.current.isDateInToday(day) else {
            limits = []
            return
        }

        if recordsOpens {
            await recordObservedOpens(state: state)
        }

        let shieldRules = appGroupStore.loadShieldRules()
        let next = TodayLimitBuilder.limits(
            rules: shieldRules.rules,
            enforcement: shieldRules.enforcement,
            appUsages: state.appUsages,
            tokensForRule: { rule in
                let selection = selectionStore.mergedSelection(scopes: rule.selectionScopes)
                // All of them: the card draws the first few and matches the day's apps
                // against the rest.
                return selection.applicationTokens.stablePrefix(selection.applicationTokens.count)
            }
        )

        guard limits != next else { return }
        withAnimation(.smooth(duration: 0.3)) { limits = next }

        recordRuleHistory(rules: shieldRules.rules, enforcement: shieldRules.enforcement, state: state, day: day)
    }

    /// Copies today into the history before midnight takes it.
    ///
    /// The enforcement record keeps one day and forgets it, which is right for enforcing a
    /// limit and useless for reading one back. This is the only place in the app that has
    /// both halves at once -- what the rule allows and what the day's report says was
    /// spent -- so it is where the day gets written down.
    private func recordRuleHistory(
        rules: [Rule],
        enforcement: RuleEnforcementState,
        state: TodayDayState,
        day: Date
    ) {
        guard !rules.isEmpty else { return }

        // Only when it has actually moved.
        //
        // This runs on every load of the screen -- and a load can retry eight times while
        // Screen Time catches up -- so writing the whole history file each pass was a
        // decode and an encode of ninety days of records nine times over for figures that
        // had not changed. The read is cheap; the write is not.
        let existing = appGroupStore.loadRuleHistory()
        var next = existing

        do {
            for rule in rules where rule.kind != .schedule {
                let tokens = Set(selectionStore.mergedSelection(scopes: rule.selectionScopes).applicationTokens)
                let matched = state.appUsages.filter { usage in
                    if let token = usage.app.applicationToken, tokens.contains(token) { return true }
                    return rule.blockedApplications.contains(usage.app.id)
                }

                let record = enforcement.record(for: rule.id, on: day)
                next.write(
                    RuleHistory.DayRecord(
                        opens: matched.reduce(0) { $0 + $1.opens },
                        seconds: matched.reduce(0) { $0 + $1.duration },
                        wasReached: record.usageLimitReachedAt != nil || rule.isShielding(given: enforcement, on: day)
                    ),
                    for: rule.id,
                    on: day
                )
            }

            next.prune(keeping: Set(rules.map(\.id)), on: day)
        }

        guard next != existing else { return }
        try? appGroupStore.saveRuleHistory(next)
    }

    /// Writes what the day's report says about each open-count rule, and puts the shield
    /// up the moment one of them runs out.
    ///
    /// This is the whole enforcement of an open count. Screen Time reports pickups per
    /// app per day and offers no event for them, so the count moves when a report lands
    /// -- which is when this screen loads. The apps are ordinary apps until then, which
    /// is the point: ten opens should be ten opens, not ten trips through a shield.
    private func recordObservedOpens(state: TodayDayState) async {
        let lookup = RuleShieldLookup(appGroupStore: appGroupStore)
        // Paused rules left out: a held rule shields nothing, so counting opens against
        // it would have it run out while it was switched off and come back already spent.
        let pauses = appGroupStore.loadRulePauseState()
        let rules = appGroupStore.loadStoredRules()
            .filter { $0.isEnabled && $0.kind == .openCountLimit && !pauses.isPaused($0.id) }
        guard !rules.isEmpty else { return }

        var didChange = false
        for rule in rules {
            // Matched by token, for the same reason the limits card matches by token: the
            // rule's apps are stored as encoded tokens (the app cannot see their bundle
            // identifiers) and the day's report stores them as bundle identifiers, so
            // comparing the two ids found nothing and every rule observed zero opens.
            let tokens = Set(selectionStore.mergedSelection(scopes: rule.selectionScopes).applicationTokens)
            let opens = state.appUsages
                .filter { usage in
                    if let token = usage.app.applicationToken, tokens.contains(token) { return true }
                    return rule.blockedApplications.contains(usage.app.id)
                }
                .reduce(0) { $0 + $1.opens }

            let stored = appGroupStore.loadRuleEnforcementState().record(for: rule.id).openCountUsed
            guard stored != opens else { continue }

            lookup.recordObservedOpens(opens, ruleID: rule.id)
            didChange = true
        }

        // Only when something moved: applying a shield is a write to ManagedSettings and
        // this runs on every load of the screen.
        if didChange {
            await pauseEngine.refreshShields()
        }
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
    ///
    /// Published rather than computed, because each group's availability has to be asked
    /// for and that cannot happen inside a getter.
    @Published private(set) var activeRoutineGroups: [TodayActiveRoutineGroup] = []

    private func refreshActiveRoutineGroups() async {
        var groups: [TodayActiveRoutineGroup] = []

        for routine in routineEngine.activeRoutines.sorted(by: { $0.startedAt < $1.startedAt }) {
            // Every scope the routine blocks through, not just its own selection: apps
            // named by an app group are held by the routine exactly like the ones picked
            // on it directly, and loading the routine scope alone left the card claiming
            // a group-only routine was holding nothing.
            let selection = selectionStore
                .blockedSelection(scopes: routine.shieldPolicy.selectionScopes)
                .applicationTokens
            // Asked per routine: its own limit, its own cooldown, its own strict mode.
            let availability = await routineEngine.breakAvailability(
                for: routine.routineID,
                trigger: .manual,
                requiresFriction: true
            )
            groups.append(
                TodayActiveRoutineGroup(
                    routine: routine,
                    tokens: selection.stablePrefix(selection.count),
                    availability: availability
                )
            )
        }

        let deduplicated = Self.deduplicatedByStrictest(groups)
        guard activeRoutineGroups != deduplicated else { return }
        activeRoutineGroups = deduplicated
    }

    /// An app two routines are holding appears once, under the stricter of them.
    ///
    /// The apps are grouped by routine, so one that both were holding was drawn twice --
    /// two rings, two captions, and two different answers to whether it could come out.
    /// Whichever row you happened to tap decided which answer you got, and the row you saw
    /// first was an accident of which routine started first.
    ///
    /// The strictest is the only one of the two that is true. An app is not free until
    /// every routine holding it lets it go, so the one that will not is the one worth
    /// showing: the other says "unlock" over an app that would stay shut.
    ///
    /// The rows keep their own order -- routines are listed as they started -- and only
    /// the apps move between them.
    private static func deduplicatedByStrictest(
        _ groups: [TodayActiveRoutineGroup]
    ) -> [TodayActiveRoutineGroup] {
        // Strictest first, and ties broken by the order they are already in, so the same
        // set of routines always resolves the same way.
        let byStrictness = groups.enumerated().sorted { lhs, rhs in
            let left = strictness(of: lhs.element)
            let right = strictness(of: rhs.element)
            return left == right ? lhs.offset < rhs.offset : left > right
        }

        var claimed = Set<AppIdentity.ID>()
        var keptTokens: [UUID: [ApplicationToken]] = [:]
        for entry in byStrictness {
            var kept: [ApplicationToken] = []
            for token in entry.element.tokens {
                let appID = AppIdentity.ID(token: token)
                guard !claimed.contains(appID) else { continue }
                claimed.insert(appID)
                kept.append(token)
            }
            keptTokens[entry.element.routine.routineID] = kept
        }

        return groups.map { group in
            TodayActiveRoutineGroup(
                routine: group.routine,
                tokens: keptTokens[group.routine.routineID] ?? [],
                availability: group.availability
            )
        }
    }

    /// Every limit shielding its apps right now, with what it is holding.
    @Published private(set) var activeLimitGroups: [TodayActiveLimitGroup] = []

    private func refreshActiveLimitGroups() async {
        let shieldRules = appGroupStore.loadShieldRules()
        var groups: [TodayActiveLimitGroup] = []

        for rule in shieldRules.rules where rule.kind != .schedule {
            // Only the ones actually holding something shut. A limit with most of its day
            // left is not blocking anything, and a card of apps that are not blocked is
            // the screen inventing a problem.
            guard rule.isShielding(given: shieldRules.enforcement) else { continue }

            let tokens = selectionStore
                .blockedSelection(scopes: rule.selectionScopes)
                .applicationTokens
            guard !tokens.isEmpty else { continue }

            groups.append(
                TodayActiveLimitGroup(
                    ruleID: rule.id,
                    name: rule.name,
                    detail: rule.kind.title,
                    tokens: tokens.stablePrefix(tokens.count),
                    // A limit opens an exception only when it was set up to. Unlike a
                    // routine there is no cooldown to count down to here: a spent limit
                    // that allows no break has no moment to wait for, it has a tomorrow.
                    availability: rule.breakPolicy.isAllowed && rule.breakPolicy.maximumBreaks > 0
                        ? .unlockable
                        : .exhausted
                )
            )
        }

        guard activeLimitGroups != groups else { return }
        activeLimitGroups = groups
    }

    /// How hard a routine is to get out of. Higher wins the app.
    ///
    /// Strict above everything: it is the one that cannot be talked out of at all. Then a
    /// spent limit, which has no moment to wait for, then a cooldown, which has one.
    private static func strictness(of group: TodayActiveRoutineGroup) -> Int {
        guard group.routine.modeSnapshot != .strict else { return 3 }

        switch group.availability {
        case .available:
            return 0
        case .unavailable(let state):
            return state.retryAt == nil ? 2 : 1
        }
    }

    /// The days being loaded right now.
    ///
    /// Two things ask for the same day at launch -- the screen's own task and the scene
    /// becoming active -- and both were served: two full pipelines, two live Screen Time
    /// queries, two of everything, racing to publish the same answer. The second one is
    /// not a different question, so it waits for nothing and simply does not run.
    private var loadingDayKeys: Set<String> = []

    func load(day: Date, force: Bool = false) async {
        await refreshRoutineCard()
        let key = DayKey(date: day)

        guard !loadingDayKeys.contains(key.id) else { return }
        loadingDayKeys.insert(key.id)
        defer { loadingDayKeys.remove(key.id) }

        // Only when there is nothing to show. A refresh used to blank the day back to
        // zeroes and then wait on Screen Time, which is why coming back to the app looked
        // like nothing had been saved: what was on screen had been thrown away before the
        // reading that would replace it had even been asked for.
        if days[key] == nil {
            withAnimation(.smooth(duration: 0.24)) {
                days[key] = .loading(day: day)
            }
            todayLogger().debug("Today load started for \(key.id, privacy: .public)")
            print("Today load started for \(key.id)")

            // The day as it was last written, straight from the App Group. It costs a
            // file read, and it means the screen has the real figures on it while the
            // live query -- which takes seconds -- is still running.
            let cachedState = await dataProvider.dayState(for: day, preferCached: true)
            if case .loaded = cachedState.loadingState {
                withAnimation(.smooth(duration: 0.28)) {
                    days[key] = cachedState
                }
                // Read-only: the limits are drawn from it, but nothing is written down
                // from a reading that may be an hour old. A stale open count written back
                // would take a shield down that should be up.
                await refreshLimits(day: day, state: cachedState, recordsOpens: false)
            }
        }

        var loadedState = await dataProvider.dayState(for: day)
        // Only when it is different.
        //
        // Every assignment here publishes, and everything watching this model rebuilds --
        // Today, and the Focus screen with it. The load retries up to eight times while
        // Screen Time catches up, and most of those attempts come back with exactly what
        // was already on screen: nine full rebuilds of two screens to show the same thing.
        if days[key] != loadedState {
            withAnimation(.smooth(duration: 0.28)) {
                days[key] = loadedState
            }
        }
        writeScoreSnapshot(day: day, state: loadedState)
        await refreshLimits(day: day, state: loadedState)
        todayLogger().debug("Today initial state for \(key.id, privacy: .public): \(String(describing: loadedState.loadingState), privacy: .public)")
        print("Today initial state for \(key.id): \(String(describing: loadedState.loadingState))")

        guard shouldRetry(after: loadedState.loadingState) else { return }

        for attempt in 1...8 {
            try? await Task.sleep(nanoseconds: 750_000_000)
            loadedState = await dataProvider.dayState(for: day)
            if days[key] != loadedState {
                withAnimation(.smooth(duration: 0.28)) {
                    days[key] = loadedState
                }
            }
            writeScoreSnapshot(day: day, state: loadedState)
            todayLogger().debug("Today retry \(attempt) for \(key.id, privacy: .public): \(String(describing: loadedState.loadingState), privacy: .public)")
            print("Today retry \(attempt) for \(key.id): \(String(describing: loadedState.loadingState))")

            await refreshLimits(day: day, state: loadedState)

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
        app: AppIdentity,
        classification: AppClassification,
        day: Date
    ) {
        let key = DayKey(date: day)
        let appID = app.id

        Task {
            await dataProvider.updateClassification(
                appID: appID,
                classification: classification
            )
            await autoFocusManager.updateMembership(for: app, classification: classification)
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
    /// How a badge should be drawn for one app: green while an unlock is possible, red
    /// with a clock while a cooldown runs, red and silent once there is nothing left.
    ///
    /// Read from the groups, which already carry each routine's own answer, and the
    /// strictest among the routines holding this app wins -- an app two routines block is
    /// not free until both of them would let it go.
    func badgeAvailability(forApp appID: AppIdentity.ID?) -> LocktyAppLockBadge.Availability {
        guard let appID else { return .unlockable }

        let holding = activeRoutineGroups.filter {
            $0.routine.shieldPolicy.blockedApplications.contains(appID)
        }
        guard !holding.isEmpty else { return .unlockable }

        for group in holding {
            if case .unavailable(let unavailable) = group.availability {
                guard let retryAt = unavailable.retryAt else { return .exhausted }
                return .cooldown(until: retryAt)
            }
        }
        return .unlockable
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

    /// Re-reads what is running, what it is holding, and what each routine will allow
    /// next -- without re-running the whole day.
    ///
    /// Granting an unlock changes all three: the app that came out, the cooldown the rest
    /// of that routine's apps now sit behind, and the break that has been spent. None of
    /// it was recomputed when the flow closed, so the card went on showing what it had
    /// read before the friction was walked -- green rings and no countdown -- and only
    /// came right on the next foreground, where `handleForeground` reloads everything.
    ///
    /// `load(day:force:)` would also do it, and does far more: a whole Screen Time day
    /// re-read for a change that touched none of it.
    func refreshActiveRoutineState() async {
        await refreshRoutineCard()
    }

    private func refreshRoutineCard() async {
        await unlockAvailability()
        await refreshActiveRoutineGroups()
        await refreshActiveLimitGroups()

        if let activeRoutine = routineEngine.activeRoutine() {
            routineCardState = TodayRoutineCardState(
                id: activeRoutine.routineID,
                name: activeRoutine.nameSnapshot,
                icon: activeRoutine.iconSnapshot,
                detailText: "Running now",
                phase: .active
            )
            return
        }

        let routines = (try? await routineRepository.routines()) ?? []
        let now = Date()
        let pauses = appGroupStore.loadRulePauseState()
        // A held routine is not upcoming: it will not start, and listing it under
        // "Scheduled" is the screen promising something that is not going to happen.
        let live = routines.filter { !pauses.isPaused($0.id, on: now) }
        let upcoming = makeUpcomingRoutines(from: live, now: now)
        if upcomingRoutines != upcoming { upcomingRoutines = upcoming }
        refreshPaused(routines: routines, pauses: pauses, now: now)
        // From the live ones, not from all of them: a held routine has no next start worth
        // announcing, and the card above the day would have gone on counting down to
        // something that is not going to happen.
        let nextRoutine = live.compactMap { routine -> (Routine, Date, TimeZone)? in
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

        let nextCardState = nextRoutine.map { routine, startDate, timeZone in
            TodayRoutineCardState(
                id: routine.id,
                name: routine.name,
                icon: routine.icon,
                detailText: upcomingText(for: startDate, timeZone: timeZone),
                phase: .upcoming
            )
        }

        if routineCardState != nextCardState { routineCardState = nextCardState }
    }

    /// Everything on hold right now: the rules and the routines together.
    ///
    /// One list because a hold is one fact -- `RulePauseState` is keyed by id and does not
    /// care which of the two the id belongs to -- and because "what is switched off at the
    /// moment" is one question however many kinds of thing can answer it.
    private func refreshPaused(routines: [Routine], pauses: RulePauseState, now: Date) {
        let rules = appGroupStore.loadStoredRules()

        var items: [TodayPausedItem] = []

        for rule in rules {
            guard let until = pauses.pauseEnd(for: rule.id, on: now) else { continue }
            items.append(
                TodayPausedItem(
                    id: rule.id,
                    name: rule.name,
                    kind: .rule,
                    symbolName: "hourglass",
                    until: until
                )
            )
        }

        for routine in routines {
            guard let until = pauses.pauseEnd(for: routine.id, on: now) else { continue }
            items.append(
                TodayPausedItem(
                    id: routine.id,
                    name: routine.name,
                    kind: .routine,
                    symbolName: routine.icon ?? "moon.zzz",
                    until: until
                )
            )
        }

        // The one coming back soonest first: it is the one about to matter again.
        let next = items.sorted { $0.until < $1.until }
        guard pausedItems != next else { return }
        withAnimation(.smooth(duration: 0.3)) { pausedItems = next }
    }

    /// Ends a hold early.
    ///
    /// The shields are re-applied straight after, because a rule coming back is a rule
    /// that has to start holding its apps again -- and nothing else would do it until the
    /// next thing happened to touch them.
    func resumePaused(_ id: UUID, day: Date) async {
        try? appGroupStore.updateRulePauseState { state in state.resume(id) }
        await startIfInsideItsWindow(routineID: id)
        await pauseEngine.refreshShields()
        await load(day: day, force: true)
    }

    /// A routine let off hold inside its own hours starts again straight away.
    ///
    /// The hold was the only reason it was not running, so lifting it is the moment to
    /// put it back. The monitor fires at the edges of the window and would not come round
    /// again until the next occurrence, which is tomorrow at the earliest -- so the
    /// schedule would have said it was running, with nothing running, for the rest of it.
    private func startIfInsideItsWindow(routineID: UUID) async {
        guard !routineEngine.isRunning(routineID),
              let routine = (try? await routineRepository.routines())?
                  .first(where: { $0.id == routineID })
        else { return }

        for trigger in routine.triggers {
            guard case .schedule(let schedule) = trigger,
                  let window = schedule.window(containing: Date())
            else { continue }

            await routineEngine.start(routine, trigger: trigger, expectedEndAt: window.end)
            return
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
                            color: routine.color,
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
        if calendar.isDateInToday(date) { return "Today" }
        if calendar.isDateInTomorrow(date) { return "Tomorrow" }

        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US")
        formatter.timeZone = calendar.timeZone
        formatter.dateFormat = "EEEE"
        return formatter.string(from: date).capitalized
    }

    private func timeLabel(for date: Date, timeZone: TimeZone) -> String {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US")
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
        timeFormatter.locale = Locale(identifier: "en_US")
        timeFormatter.timeZone = timeZone
        timeFormatter.dateFormat = "HH:mm"
        let timeText = timeFormatter.string(from: date)

        if calendar.isDateInToday(date) {
            return "Starts today · \(timeText)"
        }
        if calendar.isDateInTomorrow(date) {
            return "Starts tomorrow · \(timeText)"
        }

        let weekdayFormatter = DateFormatter()
        weekdayFormatter.locale = Locale(identifier: "en_US")
        weekdayFormatter.timeZone = timeZone
        weekdayFormatter.dateFormat = "EEEE"
        let weekdayText = weekdayFormatter.string(from: date)
        return "Starts \(weekdayText) · \(timeText)"
    }
}
