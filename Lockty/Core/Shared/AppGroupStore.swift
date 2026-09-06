import FamilyControls
import Foundation
import OSLog

enum AppGroupStoreError: LocalizedError {
    case unavailable
    case decodeFailed
    case snapshotDecodeFailed

    var errorDescription: String? {
        switch self {
        case .unavailable:
            "Lockty could not access the shared App Group container."
        case .decodeFailed:
            "Lockty could not decode the shared runtime state."
        case .snapshotDecodeFailed:
            "Lockty could not decode the shared Screen Time snapshot."
        }
    }
}

final class AppGroupStore {
    nonisolated(unsafe) private let defaults: UserDefaults?
    nonisolated(unsafe) private let fileManager: FileManager
    nonisolated private let key: String
    nonisolated private let containerURL: URL?
    nonisolated private let localFallbackURL: URL?
    nonisolated private let encoder: JSONEncoder
    nonisolated private let decoder: JSONDecoder

    nonisolated init(
        suiteName: String = SharedKeys.appGroupIdentifier,
        key: String = SharedKeys.runtimeStateKey
    ) {
        defaults = UserDefaults(suiteName: suiteName)
        fileManager = .default
        containerURL = FileManager.default
            .containerURL(forSecurityApplicationGroupIdentifier: suiteName)?
            .appendingPathComponent("SharedState", isDirectory: true)
        localFallbackURL = FileManager.default
            .urls(for: .applicationSupportDirectory, in: .userDomainMask)
            .first?
            .appendingPathComponent("LocktySharedFallback", isDirectory: true)
        encoder = JSONEncoder()
        decoder = JSONDecoder()
        self.key = key

        self.encoder.dateEncodingStrategy = .iso8601
        self.decoder.dateDecodingStrategy = .iso8601
    }

    nonisolated func loadRuntimeState() throws -> RuntimeState {
        guard let data = try readData(
            fileName: "runtime-state.json",
            legacyDefaultsKey: key
        ) else {
            Logger(subsystem: "com.gabrisp.Lockty", category: "persistence").debug("No runtime state found in shared storage.")
            return .empty
        }

        do {
            let envelope = try decoder.decode(RuntimeEnvelope.self, from: data)
            guard envelope.schemaVersion == RuntimeEnvelope.currentSchemaVersion else {
                Logger(subsystem: "com.gabrisp.Lockty", category: "persistence").error("Runtime state schema mismatch: \(envelope.schemaVersion)")
                throw AppGroupStoreError.decodeFailed
            }
            Logger(subsystem: "com.gabrisp.Lockty", category: "persistence").debug("Loaded runtime state successfully.")
            return envelope.state
        } catch {
            Logger(subsystem: "com.gabrisp.Lockty", category: "persistence").error("Failed decoding runtime state: \(error.localizedDescription, privacy: .public)")
            throw AppGroupStoreError.decodeFailed
        }
    }

    nonisolated func saveRuntimeState(_ state: RuntimeState) throws {
        let envelope = RuntimeEnvelope.current(state)
        let data = try encoder.encode(envelope)
        try writeData(
            data,
            fileName: "runtime-state.json",
            legacyDefaultsKey: key
        )
        Logger(subsystem: "com.gabrisp.Lockty", category: "persistence").notice("Saved runtime state.")
    }

    nonisolated func updateRuntimeState(_ transform: (inout RuntimeState) -> Void) throws {
        var state = try loadRuntimeState()
        transform(&state)
        state.lastUpdatedAt = Date()
        try saveRuntimeState(state)
    }

    nonisolated func resetRuntimeStateToSafeDefault() {
        var state = RuntimeState.empty
        state.recoveryFlags.insert(.corruptedPayloadReset)
        do {
            try saveRuntimeState(state)
        } catch {
            try? removeData(fileName: "runtime-state.json", legacyDefaultsKey: key)
        }
    }

    /// One day's report, from memory when it was read a moment ago.
    ///
    /// The trend builder walks a fortnight of these and the breakdown walks a month, and
    /// each of those runs several times over a single load of Today: the log was hundreds
    /// of lines of the same thirty files being decoded again. A report for a day that has
    /// passed cannot change, and today's changes at most every few minutes.
    nonisolated func loadScreenTimeReportSnapshot(for day: DayKey) throws -> ScreenTimeReportSnapshot? {
        if let cached = ReportSnapshotCache.shared.snapshot(for: day.id) {
            return cached.value
        }

        let loaded = try loadScreenTimeReportSnapshotUncached(for: day)
        ReportSnapshotCache.shared.store(loaded, for: day.id)
        return loaded
    }

    private nonisolated func loadScreenTimeReportSnapshotUncached(for day: DayKey) throws -> ScreenTimeReportSnapshot? {
        if let data = try readData(
            fileName: reportFileName(for: day),
            legacyDefaultsKey: SharedKeys.screenTimeReportSnapshotPrefix + day.id
        ) {
            do {
                let envelope = try decoder.decode(ScreenTimeReportSnapshotEnvelope.self, from: data)
                guard envelope.schemaVersion == ScreenTimeReportSnapshotEnvelope.currentSchemaVersion else {
                    Logger(subsystem: "com.gabrisp.Lockty", category: "screen-time").error("Snapshot schema mismatch for day \(day.id, privacy: .public)")
                    throw AppGroupStoreError.snapshotDecodeFailed
                }
                // Deliberately quiet. A month of the breakdown reads ninety-odd days,
                // and a `print` per day is ninety writes to stderr on whichever thread
                // asked -- which was measurably slower than the file reads themselves.
                // The failures below still say everything they said.
                return envelope.snapshot
            } catch {
                Logger(subsystem: "com.gabrisp.Lockty", category: "screen-time").error("Failed decoding snapshot for day \(day.id, privacy: .public): \(error.localizedDescription, privacy: .public)")
                throw AppGroupStoreError.snapshotDecodeFailed
            }
        }

        Logger(subsystem: "com.gabrisp.Lockty", category: "screen-time").debug("No direct snapshot file for day \(day.id, privacy: .public), checking aggregated files.")
        return loadAllScreenTimeReportSnapshots().first { snapshot in
            snapshot.day.year == day.year &&
            snapshot.day.month == day.month &&
            snapshot.day.day == day.day
        }
    }

    nonisolated func saveScreenTimeReportSnapshot(_ snapshot: ScreenTimeReportSnapshot) throws {
        ReportSnapshotCache.shared.invalidate()
        let envelope = ScreenTimeReportSnapshotEnvelope.current(snapshot)
        let data = try encoder.encode(envelope)
        try writeData(
            data,
            fileName: reportFileName(for: snapshot.day),
            legacyDefaultsKey: SharedKeys.screenTimeReportSnapshotPrefix + snapshot.day.id
        )
        Logger(subsystem: "com.gabrisp.Lockty", category: "screen-time").notice("Saved snapshot for day \(snapshot.day.id, privacy: .public) apps=\(snapshot.applications.count) segments=\(snapshot.activitySegments.count)")
    }

    nonisolated func loadAllScreenTimeReportSnapshots() -> [ScreenTimeReportSnapshot] {
        var snapshots: [ScreenTimeReportSnapshot] = []

        if let reportsDirectoryURL = reportsDirectoryURL(),
           let fileURLs = try? fileManager.contentsOfDirectory(
            at: reportsDirectoryURL,
            includingPropertiesForKeys: nil
           ) {
            for fileURL in fileURLs where fileURL.pathExtension == "json" {
                guard let data = try? Data(contentsOf: fileURL),
                      let envelope = try? decoder.decode(ScreenTimeReportSnapshotEnvelope.self, from: data),
                      envelope.schemaVersion == ScreenTimeReportSnapshotEnvelope.currentSchemaVersion else {
                    continue
                }
                snapshots.append(envelope.snapshot)
            }
        }

        if snapshots.isEmpty, let defaults {
            let keys = defaults.dictionaryRepresentation().keys
                .filter { $0.hasPrefix(SharedKeys.screenTimeReportSnapshotPrefix) }

            for key in keys {
                guard let data = defaults.data(forKey: key),
                      let envelope = try? decoder.decode(ScreenTimeReportSnapshotEnvelope.self, from: data),
                      envelope.schemaVersion == ScreenTimeReportSnapshotEnvelope.currentSchemaVersion else {
                    continue
                }
                snapshots.append(envelope.snapshot)
                try? writeData(
                    data,
                    fileName: reportFileName(for: envelope.snapshot.day),
                    legacyDefaultsKey: key
                )
            }
        }

        return snapshots.sorted(by: { lhs, rhs in
            if lhs.day.year != rhs.day.year {
                return lhs.day.year < rhs.day.year
            }
            if lhs.day.month != rhs.day.month {
                return lhs.day.month < rhs.day.month
            }
            return lhs.day.day < rhs.day.day
        })
    }

    nonisolated func loadSelectionRecords() -> [ScreenTimeSelectionRecord] {
        guard let data = (try? readData(
            fileName: "selection-records.json",
            legacyDefaultsKey: SharedKeys.screenTimeSelectionRecordsKey
        )) ?? nil else {
            return []
        }

        return (try? decoder.decode([ScreenTimeSelectionRecord].self, from: data)) ?? []
    }

    nonisolated func saveSelectionRecords(_ records: [ScreenTimeSelectionRecord]) throws {
        let data = try encoder.encode(records)
        try writeData(
            data,
            fileName: "selection-records.json",
            legacyDefaultsKey: SharedKeys.screenTimeSelectionRecordsKey
        )
    }

    nonisolated func loadPauseRuleSnapshots() -> [PauseRuleSnapshot] {
        guard let data = (try? readData(
            fileName: "pause-rule-snapshots.json",
            legacyDefaultsKey: SharedKeys.pauseRuleSnapshotsKey
        )) ?? nil else {
            return []
        }

        return (try? decoder.decode([PauseRuleSnapshot].self, from: data)) ?? []
    }

    nonisolated func savePauseRuleSnapshots(_ snapshots: [PauseRuleSnapshot]) throws {
        let data = try encoder.encode(snapshots)
        try writeData(
            data,
            fileName: "pause-rule-snapshots.json",
            legacyDefaultsKey: SharedKeys.pauseRuleSnapshotsKey
        )
    }

    // Pause flows live here rather than in Core Data. They are small, they are read by
    // the extensions as often as by the app, and adding an entity means a model version
    // -- the same reasoning that already puts routine schedules and pause snapshots in
    // this store. Worth moving when the model is next revised.
    nonisolated func loadPauseFlows() -> [PauseFlow] {
        guard let data = (try? readData(fileName: "pause-flows.json", legacyDefaultsKey: nil)) ?? nil else {
            return []
        }
        return (try? decoder.decode([PauseFlow].self, from: data)) ?? []
    }

    nonisolated func savePauseFlows(_ flows: [PauseFlow]) throws {
        let data = try encoder.encode(flows)
        try writeData(data, fileName: "pause-flows.json", legacyDefaultsKey: nil)
    }

    nonisolated func loadRoutineScheduleSnapshots() -> [RoutineScheduleSnapshot] {
        guard let data = (try? readData(
            fileName: "routine-schedule-snapshots.json",
            legacyDefaultsKey: SharedKeys.routineScheduleSnapshotsKey
        )) ?? nil else {
            return []
        }

        return (try? decoder.decode([RoutineScheduleSnapshot].self, from: data)) ?? []
    }

    nonisolated func saveRoutineScheduleSnapshots(_ snapshots: [RoutineScheduleSnapshot]) throws {
        let data = try encoder.encode(snapshots)
        try writeData(
            data,
            fileName: "routine-schedule-snapshots.json",
            legacyDefaultsKey: SharedKeys.routineScheduleSnapshotsKey
        )
    }

    nonisolated func loadUserAppGroups() -> [AppGroup] {
        guard let data = (try? readData(fileName: "user-app-groups.json", legacyDefaultsKey: nil)) ?? nil else {
            return []
        }
        return (try? decoder.decode([AppGroup].self, from: data)) ?? []
    }

    nonisolated func saveUserAppGroups(_ groups: [AppGroup]) throws {
        let data = try encoder.encode(groups)
        try writeData(data, fileName: "user-app-groups.json", legacyDefaultsKey: nil)
    }

    // MARK: - Rule history

    /// What each rule did, day by day. See `RuleHistory`.
    nonisolated func loadRuleHistory() -> RuleHistory {
        guard let data = (try? readData(fileName: "rule-history.json", legacyDefaultsKey: nil)) ?? nil,
              let history = try? decoder.decode(RuleHistory.self, from: data) else {
            return .empty
        }
        return history
    }

    nonisolated func saveRuleHistory(_ history: RuleHistory) throws {
        let data = try encoder.encode(history)
        try writeData(data, fileName: "rule-history.json", legacyDefaultsKey: nil)
    }

    nonisolated func updateRuleHistory(_ transform: (inout RuleHistory) -> Void) throws {
        var history = loadRuleHistory()
        transform(&history)
        try saveRuleHistory(history)
    }

    // MARK: - Quick actions

    /// What sits behind the plus button, in the order it was arranged.
    nonisolated func loadQuickActions() -> QuickActionSet {
        guard let data = (try? readData(fileName: "quick-actions.json", legacyDefaultsKey: nil)) ?? nil,
              let set = try? decoder.decode(QuickActionSet.self, from: data) else {
            return .default
        }
        return set
    }

    nonisolated func saveQuickActions(_ set: QuickActionSet) throws {
        let data = try encoder.encode(set)
        try writeData(data, fileName: "quick-actions.json", legacyDefaultsKey: nil)
    }

    // MARK: - Daily scores

    /// The day's finished scores, for the home screen.
    ///
    /// Written by the app whenever it works them out and read by the widget, which has no
    /// way to compute them itself.
    nonisolated func loadDailyScores() -> DailyScoreSnapshot? {
        guard let data = (try? readData(fileName: "daily-scores.json", legacyDefaultsKey: nil)) ?? nil else {
            return nil
        }
        return try? decoder.decode(DailyScoreSnapshot.self, from: data)
    }

    nonisolated func saveDailyScores(_ snapshot: DailyScoreSnapshot) throws {
        let data = try encoder.encode(snapshot)
        try writeData(data, fileName: "daily-scores.json", legacyDefaultsKey: nil)
    }

    // MARK: - Objectives

    nonisolated func loadObjectives() -> [Objective] {
        guard let data = (try? readData(fileName: "objectives.json", legacyDefaultsKey: nil)) ?? nil else {
            return []
        }
        return (try? decoder.decode([Objective].self, from: data)) ?? []
    }

    nonisolated func saveObjectives(_ objectives: [Objective]) throws {
        let data = try encoder.encode(objectives)
        try writeData(data, fileName: "objectives.json", legacyDefaultsKey: nil)
    }

    nonisolated func loadObjectiveProgress() -> ObjectiveProgressState {
        guard let data = (try? readData(fileName: "objective-progress.json", legacyDefaultsKey: nil)) ?? nil,
              let state = try? decoder.decode(ObjectiveProgressState.self, from: data) else {
            return .empty
        }
        return state
    }

    nonisolated func saveObjectiveProgress(_ state: ObjectiveProgressState) throws {
        let data = try encoder.encode(state)
        try writeData(data, fileName: "objective-progress.json", legacyDefaultsKey: nil)
    }

    nonisolated func updateObjectiveProgress(_ transform: (inout ObjectiveProgressState) -> Void) throws {
        var state = loadObjectiveProgress()
        transform(&state)
        try saveObjectiveProgress(state)
    }

    nonisolated func loadAutoFocusConfiguration() -> AutoFocusConfiguration {
        guard let data = (try? readData(fileName: "autofocus-configuration.json", legacyDefaultsKey: nil)) ?? nil,
              let configuration = try? decoder.decode(AutoFocusConfiguration.self, from: data) else {
            return .default
        }
        return configuration
    }

    nonisolated func saveAutoFocusConfiguration(_ configuration: AutoFocusConfiguration) throws {
        let data = try encoder.encode(configuration)
        try writeData(data, fileName: "autofocus-configuration.json", legacyDefaultsKey: nil)
    }

    nonisolated func loadStoredRules() -> [Rule] {
        guard let data = (try? readData(fileName: "rules.json", legacyDefaultsKey: nil)) ?? nil else {
            return []
        }
        return (try? decoder.decode([Rule].self, from: data)) ?? []
    }

    nonisolated func saveStoredRules(_ rules: [Rule]) throws {
        let data = try encoder.encode(rules)
        try writeData(data, fileName: "rules.json", legacyDefaultsKey: nil)
    }

    /// Every app name the report extension has ever written down.
    nonisolated func loadAppNameCatalog() -> AppNameCatalog {
        guard let data = (try? readData(fileName: "app-names.json", legacyDefaultsKey: nil)) ?? nil,
              let catalog = try? decoder.decode(AppNameCatalog.self, from: data) else {
            return .empty
        }
        return catalog
    }

    nonisolated func saveAppNameCatalog(_ catalog: AppNameCatalog) throws {
        let data = try encoder.encode(catalog)
        try writeData(data, fileName: "app-names.json", legacyDefaultsKey: nil)
    }

    /// Files the names in a snapshot, keeping everything already known.
    ///
    /// Called from the report extension, which is the only process that ever learns one.
    nonisolated func noteAppNames(from snapshot: ScreenTimeReportSnapshot) {
        var catalog = loadAppNameCatalog()
        let before = catalog.records
        for application in snapshot.applications {
            catalog.note(application.app)
        }
        guard catalog.records != before else { return }
        try? saveAppNameCatalog(catalog)
    }

    nonisolated func loadRulePauseState() -> RulePauseState {
        guard let data = (try? readData(fileName: "rule-pauses.json", legacyDefaultsKey: nil)) ?? nil,
              let state = try? decoder.decode(RulePauseState.self, from: data) else {
            return .empty
        }
        return state
    }

    nonisolated func saveRulePauseState(_ state: RulePauseState) throws {
        let data = try encoder.encode(state)
        try writeData(data, fileName: "rule-pauses.json", legacyDefaultsKey: nil)
    }

    nonisolated func updateRulePauseState(_ transform: (inout RulePauseState) -> Void) throws {
        var state = loadRulePauseState()
        transform(&state)
        try saveRulePauseState(state)
    }

    /// The rules the shield has to honour, and what they have spent today.
    ///
    /// Read together because they are only meaningful together: a rule says what it
    /// limits, the enforcement record says whether that limit has been hit.
    /// A rule on hold is not a rule right now: it is dropped here, at the one point every
    /// caller goes through, rather than at each of the four places that build a policy.
    nonisolated func loadShieldRules() -> (rules: [Rule], enforcement: RuleEnforcementState) {
        let pauses = loadRulePauseState()
        let rules = loadStoredRules().filter { $0.isEnabled && !pauses.isPaused($0.id) }
        return (rules, loadRuleEnforcementState())
    }

    /// The apps in the Always Allowed group.
    ///
    /// Read straight from the selection store rather than being cached in runtime state:
    /// this is the one list whose job is to override everything, so it must be the
    /// current one every time the shield is computed, not whatever was true when the
    /// running routine started.
    nonisolated func loadAlwaysAllowedApplications() -> Set<AppIdentity.ID> {
        let selection = (try? ScreenTimeSelectionStore(appGroupStore: self).load(scope: .alwaysAllowed))
            ?? FamilyActivitySelection()
        return Set(selection.applicationTokens.map(AppIdentity.ID.init(token:)))
    }

    nonisolated func loadRuleEnforcementState() -> RuleEnforcementState {
        guard let data = (try? readData(fileName: "rule-enforcement.json", legacyDefaultsKey: nil)) ?? nil,
              let state = try? decoder.decode(RuleEnforcementState.self, from: data) else {
            return .empty
        }
        return state
    }

    nonisolated func saveRuleEnforcementState(_ state: RuleEnforcementState) throws {
        let data = try encoder.encode(state)
        try writeData(data, fileName: "rule-enforcement.json", legacyDefaultsKey: nil)
    }

    nonisolated func updateRuleEnforcementState(_ transform: (inout RuleEnforcementState) -> Void) throws {
        var state = loadRuleEnforcementState()
        transform(&state)
        try saveRuleEnforcementState(state)
    }

    /// The reasons written at unlock time, oldest first.
    ///
    /// Kept so the "past answers" friction can hand them back. Capped hard: this is a
    /// record of moments someone was trying not to have, and keeping years of it would
    /// be building an archive nobody asked for.
    nonisolated func loadIntentionAnswers() -> [String] {
        guard let data = (try? readData(fileName: "intention-answers.json", legacyDefaultsKey: nil)) ?? nil,
              let answers = try? decoder.decode([String].self, from: data) else {
            return []
        }
        return answers
    }

    nonisolated func appendIntentionAnswer(_ answer: String) {
        let trimmed = answer.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }

        var answers = loadIntentionAnswers()
        answers.append(trimmed)
        answers = Array(answers.suffix(20))
        guard let data = try? encoder.encode(answers) else { return }
        try? writeData(data, fileName: "intention-answers.json", legacyDefaultsKey: nil)
    }

    /// What the block screen should say. Read by the shield extension, which cannot
    /// reach anything else the app stores.
    nonisolated func loadShieldScreenPreferences() -> ShieldScreenPreferences {
        guard let data = (try? readData(fileName: "shield-screen.json", legacyDefaultsKey: nil)) ?? nil,
              let preferences = try? decoder.decode(ShieldScreenPreferences.self, from: data) else {
            return .default
        }
        return preferences
    }

    nonisolated func saveShieldScreenPreferences(_ preferences: ShieldScreenPreferences) throws {
        let data = try encoder.encode(preferences)
        try writeData(data, fileName: "shield-screen.json", legacyDefaultsKey: nil)
    }

    nonisolated private func readData(
        fileName: String,
        legacyDefaultsKey: String?
    ) throws -> Data? {
        if let fileURL = fileURL(named: fileName), fileManager.fileExists(atPath: fileURL.path) {
            Logger(subsystem: "com.gabrisp.Lockty", category: "persistence").debug("Reading shared file \(fileName, privacy: .public) at \(fileURL.path(percentEncoded: false), privacy: .public)")
            return try Data(contentsOf: fileURL)
        }

        if let defaults, let legacyDefaultsKey, let data = defaults.data(forKey: legacyDefaultsKey) {
            Logger(subsystem: "com.gabrisp.Lockty", category: "persistence").debug("Reading shared defaults key \(legacyDefaultsKey, privacy: .public)")
            try? writeData(data, fileName: fileName, legacyDefaultsKey: legacyDefaultsKey)
            return data
        }

        Logger(subsystem: "com.gabrisp.Lockty", category: "persistence").debug("No shared data for file \(fileName, privacy: .public)")
        return nil
    }

    nonisolated private func writeData(
        _ data: Data,
        fileName: String,
        legacyDefaultsKey: String?
    ) throws {
        guard let fileURL = fileURL(named: fileName) else { throw AppGroupStoreError.unavailable }

        try ensureDirectoryExists(at: fileURL.deletingLastPathComponent())
        try data.write(to: fileURL, options: .atomic)
        if let legacyDefaultsKey {
            defaults?.set(data, forKey: legacyDefaultsKey)
        }
        Logger(subsystem: "com.gabrisp.Lockty", category: "persistence").notice("Wrote shared file \(fileName, privacy: .public) to \(fileURL.path(percentEncoded: false), privacy: .public)")
    }

    nonisolated private func removeData(
        fileName: String,
        legacyDefaultsKey: String
    ) throws {
        if let fileURL = fileURL(named: fileName), fileManager.fileExists(atPath: fileURL.path) {
            try fileManager.removeItem(at: fileURL)
        }
        defaults?.removeObject(forKey: legacyDefaultsKey)
    }

    nonisolated private func ensureDirectoryExists(at directoryURL: URL) throws {
        if !fileManager.fileExists(atPath: directoryURL.path) {
            try fileManager.createDirectory(at: directoryURL, withIntermediateDirectories: true)
        }
    }

    nonisolated private func reportsDirectoryURL() -> URL? {
        baseDirectoryURL()?.appendingPathComponent("reports", isDirectory: true)
    }

    nonisolated private func fileURL(named fileName: String) -> URL? {
        if fileName.hasPrefix("reports/") {
            return baseDirectoryURL()?.appendingPathComponent(fileName)
        }
        return baseDirectoryURL()?.appendingPathComponent(fileName)
    }

    nonisolated private func baseDirectoryURL() -> URL? {
        containerURL ?? localFallbackURL
    }

    nonisolated private func reportFileName(for day: DayKey) -> String {
        let timezone = sanitizedComponent(day.timeZoneIdentifier)
        let calendar = sanitizedComponent(String(describing: day.calendarIdentifier))
        return "reports/\(calendar)-\(timezone)-\(day.year)-\(day.month)-\(day.day).json"
    }

    nonisolated private func sanitizedComponent(_ value: String) -> String {
        value.replacingOccurrences(of: "/", with: "_")
            .replacingOccurrences(of: ":", with: "-")
            .replacingOccurrences(of: " ", with: "_")
    }
}

/// Report snapshots, briefly remembered.
///
/// Reading one is a file read and a decode of a day's worth of app activity, and the same
/// thirty days are walked by the trend, the breakdown and the insights on every load. A
/// few seconds of memory turns that from hundreds of decodes into thirty.
///
/// A class with a lock rather than an actor: every reader is `nonisolated`, and several of
/// them are extensions.
private final class ReportSnapshotCache: @unchecked Sendable {
    static let shared = ReportSnapshotCache()

    /// Long enough to cover one screen's worth of reads, short enough that a report
    /// written by the extension shows up almost at once.
    private let lifetime: TimeInterval = 5

    private let lock = NSLock()
    private var entries: [String: (value: ScreenTimeReportSnapshot?, readAt: Date)] = [:]

    func snapshot(for key: String) -> (value: ScreenTimeReportSnapshot?, readAt: Date)? {
        lock.lock()
        defer { lock.unlock() }

        guard let entry = entries[key], Date().timeIntervalSince(entry.readAt) < lifetime else { return nil }
        return entry
    }

    func store(_ snapshot: ScreenTimeReportSnapshot?, for key: String) {
        lock.lock()
        defer { lock.unlock() }
        entries[key] = (snapshot, Date())
    }

    func invalidate() {
        lock.lock()
        defer { lock.unlock() }
        entries.removeAll()
    }
}
