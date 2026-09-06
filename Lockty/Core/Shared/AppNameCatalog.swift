import Foundation

/// Every app Lockty has ever been told the name of.
///
/// Screen Time hands out an app's real name in exactly one place -- inside the report
/// extension, while a report is being built -- and nowhere else. The main app asking
/// `Application(token:)` for a name gets nil, which is why so much of the UI has to fall
/// back to `Label(token)` (a view, drawn out of process, that cannot be read as a string,
/// put in a sentence, or sorted on).
///
/// So the extension writes down what it knows: the id, the bundle identifier and the
/// name. The icon is not here and cannot be -- it is drawn from the token by the system,
/// and there is no way to get bytes for it -- which is exactly why the token is kept
/// alongside everywhere an icon is needed.
///
/// It only ever grows. An app that stops being used this week keeps its name, because the
/// name is a fact about the app rather than about the week.
nonisolated struct AppNameRecord: Codable, Hashable {
    var bundleIdentifier: String?
    var displayName: String
    /// When it was last confirmed, so a name that changes (an app renaming itself) is not
    /// held onto for ever by whichever record happened to be written first.
    var updatedAt: Date

    init(bundleIdentifier: String?, displayName: String, updatedAt: Date = Date()) {
        self.bundleIdentifier = bundleIdentifier
        self.displayName = displayName
        self.updatedAt = updatedAt
    }
}

nonisolated struct AppNameCatalog: Codable, Hashable {
    var records: [String: AppNameRecord]

    init(records: [String: AppNameRecord] = [:]) {
        self.records = records
    }

    static let empty = AppNameCatalog()

    nonisolated func record(for id: AppIdentity.ID) -> AppNameRecord? {
        records[id.rawValue]
    }

    /// Files what an identity knows about itself, when it knows anything worth keeping.
    ///
    /// A name derived from a bundle id is not worth keeping -- it is what the app falls
    /// back to when it has nothing, and writing it down would freeze the fallback in
    /// place where the real name might arrive tomorrow.
    nonisolated mutating func note(_ app: AppIdentity, now: Date = Date()) {
        guard !app.displayName.isEmpty else { return }
        let isDerived = app.bundleIdentifier.map { $0.localizedCaseInsensitiveContains(app.displayName) } ?? false
        guard !isDerived else { return }

        records[app.id.rawValue] = AppNameRecord(
            bundleIdentifier: app.bundleIdentifier,
            displayName: app.displayName,
            updatedAt: now
        )
    }
}

extension AppIdentity {
    /// The same identity with whatever the catalogue knows filled in.
    ///
    /// Only fills gaps: a name the identity already carries is the fresher of the two,
    /// since it came from the report being read right now.
    nonisolated func resolved(with catalog: AppNameCatalog) -> AppIdentity {
        guard let record = catalog.record(for: id) else { return self }

        var resolved = self
        if bundleIdentifier == nil { resolved.bundleIdentifier = record.bundleIdentifier }

        // Replaced only when what we have is a stand-in. The test is the same one the
        // catalogue uses to decide what is worth writing down.
        let isDerived = bundleIdentifier.map { $0.localizedCaseInsensitiveContains(displayName) } ?? true
        if isDerived { resolved.displayName = record.displayName }

        return resolved
    }
}
