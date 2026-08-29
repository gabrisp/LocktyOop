import Foundation

/// The pause a routine offers on anything it blocks.
///
/// One flow per routine rather than one per app: the shield can't tell which of the
/// routine's apps deserves which flow, and the user shouldn't have to configure the same
/// countdown a dozen times. This replaces the standalone per-app PauseRule, which is
/// still in the codebase but no longer has a way in.
nonisolated struct RoutinePausePolicy: Codable, Hashable {
    var isEnabled: Bool
    var steps: [PauseStep]
    /// How long the app stays open once the flow is completed.
    var allowanceDuration: TimeInterval
    var relockAfterAllowance: Bool

    init(
        isEnabled: Bool = false,
        steps: [PauseStep] = [],
        allowanceDuration: TimeInterval = 5 * 60,
        relockAfterAllowance: Bool = true
    ) {
        self.isEnabled = isEnabled
        self.steps = steps
        self.allowanceDuration = allowanceDuration
        self.relockAfterAllowance = relockAfterAllowance
    }

    static let defaultSteps: [PauseStep] = [
        .countdown(CountdownConfiguration(duration: 10)),
        .confirmation(ConfirmationConfiguration())
    ]

    /// Disabled, so a routine that hasn't been given a pause blocks outright.
    static let off = RoutinePausePolicy(isEnabled: false, steps: [])

    var offersPause: Bool {
        isEnabled && !steps.isEmpty
    }
}
