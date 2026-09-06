import Foundation

/// A rule or a routine that is on hold, and until when.
///
/// Both are the same fact: `RulePauseState` is keyed by id and does not care whether the
/// id belongs to a rule or a routine, because holding either one means the same thing --
/// nothing it says applies until the hold ends.
struct TodayPausedItem: Identifiable, Equatable {
    enum Kind: Equatable {
        case rule
        case routine

        /// What it is, for the line under the name.
        var noun: String {
            switch self {
            case .rule: "Limit"
            case .routine: "Routine"
            }
        }
    }

    let id: UUID
    let name: String
    let kind: Kind
    let symbolName: String
    let until: Date

    /// "Paused until Fri 09:00". The end is the whole point: a hold with no end on screen
    /// is indistinguishable from something switched off and forgotten.
    var detail: String {
        "\(kind.noun) · until \(LocktyDateFormatting.shortDayAndTime(until))"
    }
}
