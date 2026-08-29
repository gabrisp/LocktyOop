import Foundation

/// A saved way of pausing: a name and the steps someone goes through before an app
/// opens.
///
/// It names no app and no routine. A flow is written once and then picked by whichever
/// routine wants it, and from then on it applies to everything that routine blocks --
/// which is why the per-app PauseRule it replaces could never be reused.
nonisolated struct PauseFlow: Codable, Hashable, Identifiable {
    let id: UUID
    var name: String
    var icon: String?
    var steps: [PauseStep]
    /// How long the app stays open once the flow is completed.
    var allowanceDuration: TimeInterval
    var relockAfterAllowance: Bool
    var createdAt: Date
    var updatedAt: Date

    init(
        id: UUID = UUID(),
        name: String,
        icon: String? = nil,
        steps: [PauseStep] = PauseFlow.defaultSteps,
        allowanceDuration: TimeInterval = 5 * 60,
        relockAfterAllowance: Bool = true,
        createdAt: Date = Date(),
        updatedAt: Date = Date()
    ) {
        self.id = id
        self.name = name
        self.icon = icon
        self.steps = steps
        self.allowanceDuration = allowanceDuration
        self.relockAfterAllowance = relockAfterAllowance
        self.createdAt = createdAt
        self.updatedAt = updatedAt
    }

    /// Wait, then confirm. Every flow starts from this and is customised from there.
    static let defaultSteps: [PauseStep] = [
        .countdown(CountdownConfiguration(duration: 5)),
        .confirmation(ConfirmationConfiguration())
    ]

    var allowanceMinutes: Int {
        max(1, Int(allowanceDuration / 60))
    }

    /// What the flow does, in order, for a card that has one line to say it in.
    var summary: String {
        steps.map(\.title).joined(separator: " · ")
    }

    /// The policy a routine applies when it uses this flow.
    var policy: RoutinePausePolicy {
        RoutinePausePolicy(
            isEnabled: true,
            steps: steps,
            allowanceDuration: allowanceDuration,
            relockAfterAllowance: relockAfterAllowance
        )
    }
}
