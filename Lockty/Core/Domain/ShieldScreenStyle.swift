import Foundation

/// What the block screen says when it stops you.
///
/// The shield is the only part of Lockty most people see on a bad day, and it is the same
/// three lines every time -- which is exactly when a message stops being read. These are
/// different things to say at that moment, not different jokes: what it costs, what you
/// meant to do instead, or nothing at all.
///
/// Deliberately not a shop of quote packs. A shield that reads you a celebrity aphorism
/// is entertainment at the moment you are trying not to be entertained, and it teaches
/// people to open blocked apps to see what it will say next.
nonisolated enum ShieldScreenStyle: String, Codable, CaseIterable, Identifiable, Sendable {
    /// What is running and what you can do about it. The default, and the only one that
    /// answers "why can I not open this".
    case plain
    /// The same, plus what this app has already taken today.
    case cost
    /// The same, plus the reason you gave when you set the routine up.
    case intention
    /// The name of the app and nothing else. For people who find any message an argument
    /// worth having.
    case quiet

    var id: String { rawValue }

    var title: String {
        switch self {
        case .plain: "Plain"
        case .cost: "What it costs"
        case .intention: "Your reason"
        case .quiet: "Quiet"
        }
    }

    var subtitle: String {
        switch self {
        case .plain:
            "Says which routine is running and what you can do."
        case .cost:
            "Adds how long you have already spent in this app today."
        case .intention:
            "Adds the reason you wrote when you set the routine up."
        case .quiet:
            "Just the app's name and the buttons. No message at all."
        }
    }

    var systemImage: String {
        switch self {
        case .plain: "shield.lefthalf.filled"
        case .cost: "hourglass"
        case .intention: "quote.opening"
        case .quiet: "moon"
        }
    }

    static let `default` = ShieldScreenStyle.plain
}

/// The parts of the block screen the person chose, kept together so the extension reads
/// one value rather than four keys.
nonisolated struct ShieldScreenPreferences: Codable, Hashable, Sendable {
    var style: ShieldScreenStyle
    /// The line the `.intention` style shows. Empty falls back to `.plain`, since a
    /// blank reason is not a reason.
    var intention: String

    init(style: ShieldScreenStyle = .default, intention: String = "") {
        self.style = style
        self.intention = intention
    }

    static let `default` = ShieldScreenPreferences()

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        style = try container.decodeIfPresent(ShieldScreenStyle.self, forKey: .style) ?? .default
        intention = try container.decodeIfPresent(String.self, forKey: .intention) ?? ""
    }
}
