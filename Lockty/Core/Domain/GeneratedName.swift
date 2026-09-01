import Foundation

/// A name to start from, so nothing has to be built from a blank field.
///
/// Every one of these is a real, usable name rather than a placeholder: it is written
/// into the field, the header shows it, and saving without touching it produces something
/// sensible. The user can edit it exactly as if they had typed it.
enum LocktyGeneratedName {
    /// A routine named after when it runs.
    ///
    /// The hour is the most useful thing known at the moment a routine is created --
    /// "Routine 3" tells you nothing later, and "Morning" tells you what it is for.
    nonisolated static func routine(startHour: Int, existing: [String]) -> String {
        let base: String
        switch startHour {
        case 5..<12: base = "Morning"
        case 12..<15: base = "Midday"
        case 15..<20: base = "Afternoon"
        case 20..<24: base = "Evening"
        default: base = "Late night"
        }
        return unique(base, among: existing)
    }

    /// A rule named after what it limits.
    nonisolated static func rule(kind: RuleKind, existing: [String]) -> String {
        let base: String
        switch kind {
        case .schedule: base = "Schedule"
        case .openCountLimit: base = "Opens"
        case .dailyUsageLimit: base = "Daily use"
        case .sessionDurationLimit: base = "Session"
        }
        return unique(base, among: existing)
    }

    /// The base, or the base with the first free number after it.
    ///
    /// Numbered only when it has to be. A first routine called "Morning 2" implies a
    /// second one that does not exist; the number earns its place when there is
    /// something to tell apart.
    nonisolated static func unique(_ base: String, among existing: [String]) -> String {
        let taken = Set(
            existing.map { $0.trimmingCharacters(in: .whitespacesAndNewlines).lowercased() }
        )
        guard taken.contains(base.lowercased()) else { return base }

        var index = 2
        while taken.contains("\(base) \(index)".lowercased()) {
            index += 1
        }
        return "\(base) \(index)"
    }
}
