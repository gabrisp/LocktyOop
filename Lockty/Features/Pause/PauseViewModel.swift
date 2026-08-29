import Foundation
import Combine

@MainActor
final class PauseViewModel: ObservableObject {
    let context: PauseContext
    private let engine: PauseEngine
    private var countdownTask: Task<Void, Never>?
    private var hasSeededCurrentCountdown = false

    @Published var currentStepIndex: Int = 0
    @Published var remainingSeconds: Int = 0
    @Published var completedBreaths: Int = 0
    @Published var intentionText = ""
    /// Total for the countdown step currently on screen, so the view can scale its
    /// haptics by how far through the wait we are.
    @Published private(set) var countdownTotalSeconds: Int = 0
    /// The moment the running countdown reaches zero. Nil whenever it is not running --
    /// while backgrounded, for instance -- which is what keeps it from ticking away
    /// off screen.
    private var deadline: Date?

    init(context: PauseContext, engine: PauseEngine) {
        self.context = context
        self.engine = engine
        if let firstCountdown = context.steps.compactMap({ step -> CountdownConfiguration? in
            guard case .countdown(let configuration) = step else { return nil }
            return configuration
        }).first {
            remainingSeconds = Int(firstCountdown.duration)
            countdownTotalSeconds = remainingSeconds
        }
    }

    var currentStep: PauseStep? {
        guard context.steps.indices.contains(currentStepIndex) else { return nil }
        return context.steps[currentStepIndex]
    }

    var titleText: String {
        context.displayName
    }

    var primaryText: String {
        guard let currentStep else { return "Ready" }
        switch currentStep {
        case .countdown:
            return "\(remainingSeconds)"
        case .breathing(let configuration):
            return "\(completedBreaths)/\(configuration.breathCount)"
        case .intention:
            return "State your intention"
        case .confirmation:
            return "Still continue?"
        }
    }

    var secondaryText: String {
        guard let currentStep else { return "Pause completed." }
        switch currentStep {
        case .countdown:
            return "Wait before opening \(context.displayName)."
        case .breathing(let configuration):
            return "Take \(configuration.breathCount) calm breaths."
        case .intention(let configuration):
            return configuration.prompt
        case .confirmation(let configuration):
            return configuration.prompt
        }
    }

    var showsIntentionField: Bool {
        guard let currentStep else { return false }
        if case .intention = currentStep { return true }
        return false
    }

    var canAdvance: Bool {
        guard let currentStep else { return true }
        switch currentStep {
        case .countdown:
            return remainingSeconds == 0
        case .breathing(let configuration):
            return completedBreaths >= configuration.breathCount
        case .intention(let configuration):
            if !configuration.isRequired {
                return true
            }
            let trimmed = intentionText.trimmingCharacters(in: .whitespacesAndNewlines)
            let minimumLength = configuration.minimumLength ?? 1
            return trimmed.count >= minimumLength
        case .confirmation:
            return true
        }
    }

    var continueButtonTitle: String {
        if isFinalDecisionStep {
            return "Continue for \(LocktyDurationFormatter.abbreviated(context.allowanceDuration))"
        }
        return "Continue"
    }

    var isFinalDecisionStep: Bool {
        guard let currentStep else { return false }
        if case .confirmation = currentStep {
            return true
        }
        return currentStepIndex == context.steps.count - 1
    }

    var isCountingDown: Bool {
        guard case .countdown? = currentStep else { return false }
        return true
    }

    func startIfNeeded() {
        guard case .countdown(let configuration)? = currentStep else { return }
        guard countdownTask == nil else { return }
        // Only seed the total on a fresh step; coming back from the background must
        // resume where it stopped, not restart the wait.
        if !hasSeededCurrentCountdown {
            remainingSeconds = Int(configuration.duration)
            countdownTotalSeconds = remainingSeconds
            hasSeededCurrentCountdown = true
        }
        engine.beginThinking(context)
        resume()
    }

    /// Freezes the countdown when the app leaves the foreground. Without this the sleep
    /// loop kept its own schedule across a suspend and the number jumped on return.
    func pause() {
        countdownTask?.cancel()
        countdownTask = nil
        deadline = nil
    }

    /// Picks the countdown back up from the second it stopped on.
    func resume() {
        guard isCountingDown, remainingSeconds > 0, countdownTask == nil else { return }
        let target = Date().addingTimeInterval(TimeInterval(remainingSeconds))
        deadline = target

        countdownTask = Task { [weak self] in
            while let self, !Task.isCancelled, self.deadline == target {
                try? await Task.sleep(for: .milliseconds(200))
                guard !Task.isCancelled, self.deadline == target else { return }

                // Derived from the deadline rather than decremented, so a late wake-up
                // lands on the right second instead of drifting.
                let next = max(0, Int(target.timeIntervalSinceNow.rounded(.up)))
                guard next != self.remainingSeconds else { continue }
                self.remainingSeconds = next
                self.engine.updateCountdown(context: self.context, remainingSeconds: next)

                if next == 0 {
                    self.countdownTask = nil
                    self.deadline = nil
                    self.moveToNextStepIfNeeded()
                    return
                }
            }
        }
    }

    func registerBreath() {
        guard case .breathing(let configuration)? = currentStep else { return }
        completedBreaths = min(completedBreaths + 1, configuration.breathCount)
        if completedBreaths >= configuration.breathCount {
            moveToNextStepIfNeeded()
        }
    }

    func advance() async -> Bool {
        guard canAdvance else { return false }
        if isFinalDecisionStep {
            await engine.allowTemporarily(context, intention: sanitizedIntention)
            return true
        }
        moveToNextStepIfNeeded()
        return false
    }

    func stayLocked() async -> Bool {
        pause()
        await engine.cancel(context, intention: sanitizedIntention)
        return true
    }

    private var sanitizedIntention: String? {
        let trimmed = intentionText.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }

    private func moveToNextStepIfNeeded() {
        guard currentStepIndex < context.steps.count - 1 else { return }
        currentStepIndex += 1
        completedBreaths = 0
        remainingSeconds = 0
        countdownTotalSeconds = 0
        hasSeededCurrentCountdown = false
        pause()
        startIfNeeded()
    }
}
