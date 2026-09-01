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
    /// How long the breathe that opens the flow lasts.
    ///
    /// A setting, not a step. Every unlock starts on the same breathe, so putting it in
    /// the step list meant it could be added twice, moved after a puzzle, or left out of
    /// a flow that would still open with one anyway -- three ways of saying something the
    /// flow does not let you choose.
    var breatheSeconds: Int

    init(
        isEnabled: Bool = false,
        steps: [PauseStep] = [],
        allowanceDuration: TimeInterval = 5 * 60,
        relockAfterAllowance: Bool = true,
        breatheSeconds: Int = LocktyBreathe.minimumSeconds
    ) {
        self.isEnabled = isEnabled
        self.steps = steps
        self.allowanceDuration = allowanceDuration
        self.relockAfterAllowance = relockAfterAllowance
        self.breatheSeconds = LocktyBreathe.clamped(breatheSeconds)
    }

    // Written by hand so a policy stored before the breathe was a setting still decodes
    // instead of throwing and taking the routine's whole pause with it.
    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        isEnabled = try container.decode(Bool.self, forKey: .isEnabled)
        steps = try container.decode([PauseStep].self, forKey: .steps)
        allowanceDuration = try container.decode(TimeInterval.self, forKey: .allowanceDuration)
        relockAfterAllowance = try container.decode(Bool.self, forKey: .relockAfterAllowance)
        breatheSeconds = LocktyBreathe.clamped(
            try container.decodeIfPresent(Int.self, forKey: .breatheSeconds) ?? LocktyBreathe.minimumSeconds
        )
    }

    static let defaultSteps: [PauseStep] = [
        .countdown(CountdownConfiguration(duration: 10)),
        .confirmation(ConfirmationConfiguration())
    ]

    /// Disabled, so a routine that hasn't been given a pause blocks outright.
    static let off = RoutinePausePolicy(isEnabled: false, steps: [])

    /// Wait, then confirm. What every unlock falls back to when no flow can be read --
    /// a shield with no way through it is a bug, not a stricter setting.
    static let standard = RoutinePausePolicy(isEnabled: true, steps: defaultSteps)

    var offersPause: Bool {
        isEnabled && !steps.isEmpty
    }
}
