import ManagedSettings
import SwiftUI

/// Something the app wants to say, shown out of the Dynamic Island.
///
/// Mostly reports about something that just happened elsewhere -- a routine starting, a
/// score moving, an unlock being granted -- which should be seen and then be gone,
/// without taking the screen away from whatever is on it. Deliberately not an alert or a
/// banner in the scroll view.
///
/// One of them is a question: the shield asking to be let past. That one carries an
/// `action`, stays up longer, and is dismissed by being answered.
struct LocktyToast: Identifiable, Equatable {
    let id: String
    var leading: Leading
    var title: String
    var message: String
    /// A number the toast counts to, rendered with a numeric transition.
    var value: Int?
    /// Trails the value, e.g. "%" or "pts".
    var valueSuffix: String?
    /// 0...1. Draws a bar under the message when present.
    var progress: Double?
    /// What tapping it does, when it is a question rather than a report.
    ///
    /// Compared by `id` alone rather than by the closure, which cannot be compared at
    /// all -- two toasts with the same id are the same toast whatever they were built to
    /// do.
    var action: (@MainActor () -> Void)?
    /// What the tap would do, shown as a hint under the message. Nil for a report.
    var actionTitle: String?
    /// What the whole toast is tinted by: the icon, its halo, the value and the bar.
    ///
    /// Carried on the toast rather than derived per part, so a toast cannot end up with a
    /// red icon over a green bar -- one colour is what makes it read as one report.
    var accent: Color
    /// How long it stays up.
    var duration: Duration

    /// What sits on the left. An app's own icon when the toast is about one specific app,
    /// because a padlock glyph says far less than the icon of the thing being unlocked.
    enum Leading: Equatable {
        case symbol(String, Color)
        case appIcon(ApplicationToken)
    }

    init(
        id: String = UUID().uuidString,
        leading: Leading,
        title: String,
        message: String,
        value: Int? = nil,
        valueSuffix: String? = nil,
        progress: Double? = nil,
        accent: Color? = nil,
        duration: Duration = .seconds(2.6),
        action: (@MainActor () -> Void)? = nil,
        actionTitle: String? = nil
    ) {
        self.id = id
        self.leading = leading
        self.title = title
        self.message = message
        self.value = value
        self.valueSuffix = valueSuffix
        self.progress = progress
        self.action = action
        self.actionTitle = actionTitle
        // Defaults to the symbol's own colour, which is the one the toast was built
        // around anyway; an app icon has no colour to take, so it falls back to green.
        self.accent = accent ?? {
            if case .symbol(_, let tint) = leading { return tint }
            return LocktyColors.productive
        }()
        self.duration = duration
    }

    // By id, because a closure has no equality. Two toasts sharing an id are the same
    // toast; the action is what it does, not what it is.
    static func == (lhs: LocktyToast, rhs: LocktyToast) -> Bool {
        lhs.id == rhs.id
            && lhs.title == rhs.title
            && lhs.message == rhs.message
            && lhs.value == rhs.value
            && lhs.progress == rhs.progress
    }
}

extension LocktyToast {
    /// The routine's own icon, not a generic play glyph: the whole point of choosing one
    /// is to recognise the routine at a glance, and this is the moment it starts.
    static func routineStarted(name: String, icon: String?) -> LocktyToast {
        LocktyToast(
            leading: .symbol(icon?.isEmpty == false ? icon! : "bolt.fill", LocktyColors.productive),
            title: name,
            message: "Mode started"
        )
    }

    static func routineEnded(name: String) -> LocktyToast {
        LocktyToast(
            leading: .symbol("checkmark", LocktyColors.productive),
            title: name,
            message: "Mode finished",
            accent: LocktyColors.secondaryText
        )
    }

    /// A score that moved. The number counts to where it landed and the bar fills to it,
    /// so the toast shows the change rather than just asserting one happened.
    ///
    /// Coloured by where the score ended up, not by the fact that it rose. Green on a 30
    /// would be congratulating a bad day for being slightly less bad -- the bands are
    /// `DailyScoreTone`'s, the same ones the rock and the cards are judged by.
    static func scoreRose(to score: Int, from previous: Int) -> LocktyToast {
        let tint: Color
        switch DailyScoreTone.tone(for: Double(score)) {
        case .weak: tint = LocktyColors.unproductive
        case .balanced: tint = LocktyColors.warning
        case .strong: tint = LocktyColors.productive
        }

        return LocktyToast(
            leading: .symbol("chart.line.uptrend.xyaxis", tint),
            title: "Productivity",
            message: "Up \(score - previous) points",
            value: score,
            valueSuffix: "%",
            progress: Double(score) / 100,
            accent: tint,
            duration: .seconds(3.2)
        )
    }

    static func alwaysAllowedLocked() -> LocktyToast {
        LocktyToast(
            leading: .symbol("lock.fill", LocktyColors.warning),
            title: "Always Allowed",
            message: "End the running routine to edit this",
            accent: LocktyColors.warning
        )
    }

    /// Refused because one of the chosen apps is one nothing may block.
    static func blockedAppIsAlwaysAllowed(names: [String]) -> LocktyToast {
        let subject = names.count == 1
            ? (names.first ?? "Una app")
            : "\(names.count) apps"
        return LocktyToast(
            leading: .symbol("exclamationmark.triangle.fill", LocktyColors.error),
            title: subject,
            message: "It is in Always Allowed and cannot be blocked",
            accent: LocktyColors.error,
            duration: .seconds(3.2)
        )
    }

    /// The shield asking to be let past. The one toast that is a question.
    ///
    /// Longer on screen than a report, because a report only has to be noticed and this
    /// has to be answered -- and the answer is a tap on the toast itself.
    static func unlockRequested(
        context: PauseContext,
        action: @escaping @MainActor () -> Void
    ) -> LocktyToast {
        LocktyToast(
            id: "unlock-request-\(context.id.uuidString)",
            leading: context.applicationToken.map { .appIcon($0) } ?? .symbol("lock.fill", LocktyColors.warning),
            title: context.displayName,
            message: "Wants to be unlocked",
            accent: LocktyColors.warning,
            duration: .seconds(6),
            action: action,
            actionTitle: "Start friction"
        )
    }

    /// The same request, refused before it was opened.
    ///
    /// Shown rather than swallowed: the shield was just tapped, and nothing happening at
    /// all reads as the app having failed to open rather than as the answer being no.
    static func unlockRefused(
        context: PauseContext,
        state: BreakUnavailableState
    ) -> LocktyToast {
        LocktyToast(
            id: "unlock-refused-\(context.id.uuidString)",
            leading: context.applicationToken.map { .appIcon($0) } ?? .symbol("lock.fill", LocktyColors.error),
            title: state.title,
            message: state.message,
            accent: LocktyColors.error,
            duration: .seconds(3.4)
        )
    }

    static func unlockGranted(token: ApplicationToken?, displayName: String, minutes: Int) -> LocktyToast {
        LocktyToast(
            leading: token.map { .appIcon($0) } ?? .symbol("lock.open.fill", LocktyColors.productive),
            title: displayName,
            message: minutes == 1 ? "Unlocked for 1 minute" : "Unlocked for \(minutes) minutes",
            accent: LocktyColors.productive
        )
    }
}

/// The one place a toast is asked for.
///
/// A single current toast rather than a queue: two of these landing at once would fight
/// over the same island, and the newer one is always the more interesting.
@MainActor
@Observable
final class LocktyToastCenter {
    private(set) var current: LocktyToast?
    var isPresented = false

    private var dismissalTask: Task<Void, Never>?

    func show(_ toast: LocktyToast) {
        dismissalTask?.cancel()
        current = toast
        isPresented = true

        dismissalTask = Task { [duration = toast.duration] in
            try? await Task.sleep(for: duration)
            guard !Task.isCancelled else { return }
            isPresented = false
        }
    }

    func dismiss() {
        dismissalTask?.cancel()
        isPresented = false
    }
}
