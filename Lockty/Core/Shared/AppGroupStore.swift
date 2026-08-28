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
            print("Loaded runtime state successfully.")
            return envelope.state
        } catch {
            Logger(subsystem: "com.gabrisp.Lockty", category: "persistence").error("Failed decoding runtime state: \(error.localizedDescription, privacy: .public)")
            print("Failed decoding runtime state: \(error.localizedDescription)")
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
        print("Saved runtime state.")
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

    nonisolated func loadScreenTimeReportSnapshot(for day: DayKey) throws -> ScreenTimeReportSnapshot? {
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
                Logger(subsystem: "com.gabrisp.Lockty", category: "screen-time").notice("Loaded snapshot for day \(day.id, privacy: .public) apps=\(envelope.snapshot.applications.count)")
                print("Loaded snapshot for day \(day.id) apps=\(envelope.snapshot.applications.count)")
                return envelope.snapshot
            } catch {
                Logger(subsystem: "com.gabrisp.Lockty", category: "screen-time").error("Failed decoding snapshot for day \(day.id, privacy: .public): \(error.localizedDescription, privacy: .public)")
                print("Failed decoding snapshot for day \(day.id): \(error.localizedDescription)")
                throw AppGroupStoreError.snapshotDecodeFailed
            }
        }

        Logger(subsystem: "com.gabrisp.Lockty", category: "screen-time").debug("No direct snapshot file for day \(day.id, privacy: .public), checking aggregated files.")
        print("No direct snapshot file for day \(day.id), checking aggregated files.")
        return loadAllScreenTimeReportSnapshots().first { snapshot in
            snapshot.day.year == day.year &&
            snapshot.day.month == day.month &&
            snapshot.day.day == day.day
        }
    }

    nonisolated func saveScreenTimeReportSnapshot(_ snapshot: ScreenTimeReportSnapshot) throws {
        let envelope = ScreenTimeReportSnapshotEnvelope.current(snapshot)
        let data = try encoder.encode(envelope)
        try writeData(
            data,
            fileName: reportFileName(for: snapshot.day),
            legacyDefaultsKey: SharedKeys.screenTimeReportSnapshotPrefix + snapshot.day.id
        )
        Logger(subsystem: "com.gabrisp.Lockty", category: "screen-time").notice("Saved snapshot for day \(snapshot.day.id, privacy: .public) apps=\(snapshot.applications.count) segments=\(snapshot.activitySegments.count)")
        print("Saved snapshot for day \(snapshot.day.id) apps=\(snapshot.applications.count) segments=\(snapshot.activitySegments.count)")
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
        print("Saved selection records count=\(records.count)")
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

    nonisolated private func readData(
        fileName: String,
        legacyDefaultsKey: String
    ) throws -> Data? {
        if let fileURL = fileURL(named: fileName), fileManager.fileExists(atPath: fileURL.path) {
            Logger(subsystem: "com.gabrisp.Lockty", category: "persistence").debug("Reading shared file \(fileName, privacy: .public) at \(fileURL.path(percentEncoded: false), privacy: .public)")
            print("Reading shared file \(fileName) at \(fileURL.path(percentEncoded: false))")
            return try Data(contentsOf: fileURL)
        }

        if let defaults, let data = defaults.data(forKey: legacyDefaultsKey) {
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
        legacyDefaultsKey: String
    ) throws {
        guard let fileURL = fileURL(named: fileName) else { throw AppGroupStoreError.unavailable }

        try ensureDirectoryExists(at: fileURL.deletingLastPathComponent())
        try data.write(to: fileURL, options: .atomic)
        defaults?.set(data, forKey: legacyDefaultsKey)
        Logger(subsystem: "com.gabrisp.Lockty", category: "persistence").notice("Wrote shared file \(fileName, privacy: .public) to \(fileURL.path(percentEncoded: false), privacy: .public)")
        print("Wrote shared file \(fileName) to \(fileURL.path(percentEncoded: false))")
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
