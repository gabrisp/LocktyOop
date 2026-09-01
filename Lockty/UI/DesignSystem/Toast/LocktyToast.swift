import ManagedSettings
import SwiftUI

/// Something the app wants to say, shown out of the Dynamic Island.
///
/// Deliberately not an alert or a banner in the scroll view: these are all reports about
/// something that just happened elsewhere -- a routine starting, a score moving, an
/// unlock being granted -- and none of them is a question. They should be seen and then
/// be gone, without taking the screen away from whatever is on it.
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
        duration: Duration = .seconds(2.6)
    ) {
        self.id = id
        self.leading = leading
        self.title = title
        self.message = message
        self.value = value
        self.valueSuffix = valueSuffix
        self.progress = progress
        self.duration = duration
    }
}

extension LocktyToast {
    static func routineStarted(name: String, icon: String?) -> LocktyToast {
        LocktyToast(
            leading: .symbol(icon?.isEmpty == false ? icon! : "repeat", LocktyColors.productive),
            title: name,
            message: "Modo iniciado"
        )
    }

    static func routineEnded(name: String) -> LocktyToast {
        LocktyToast(
            leading: .symbol("stop.circle", LocktyColors.secondaryText),
            title: name,
            message: "Modo finalizado"
        )
    }

    /// A score that moved. The number counts to where it landed and the bar fills to it,
    /// so the toast shows the change rather than just asserting one happened.
    static func scoreRose(to score: Int, from previous: Int) -> LocktyToast {
        LocktyToast(
            leading: .symbol("arrow.up.right", LocktyColors.productive),
            title: "Productivity",
            message: "Ha subido \(score - previous) puntos",
            value: score,
            valueSuffix: "%",
            progress: Double(score) / 100,
            duration: .seconds(3.2)
        )
    }

    static func unlockGranted(token: ApplicationToken?, displayName: String, minutes: Int) -> LocktyToast {
        LocktyToast(
            leading: token.map { .appIcon($0) } ?? .symbol("lock.open.fill", LocktyColors.productive),
            title: displayName,
            message: minutes == 1 ? "Desbloqueado 1 minuto" : "Desbloqueado \(minutes) minutos"
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
