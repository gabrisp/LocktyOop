import Foundation
import Observation

@MainActor
@Observable
final class PauseViewModel {
    let context: PauseContext
    private let engine: PauseEngine
    private var countdownTask: Task<Void, Never>?

    var currentStepIndex: Int = 0
    var remainingSeconds: Int = 0
    var completedBreaths: Int = 0
    var intentionText = ""

    init(context: PauseContext, engine: PauseEngine) {
        self.context = context
        self.engine = engine
        if let firstCountdown = context.steps.compactMap({ step -> CountdownConfiguration? in
            guard case .countdown(let configuration) = step else { return nil }
            return configuration
        }).first {
            remainingSeconds = Int(firstCountdown.duration)
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

    func startIfNeeded() {
        guard case .countdown(let configuration)? = currentStep else { return }
        guard countdownTask == nil else { return }
        remainingSeconds = Int(configuration.duration)
        engine.beginThinking(context)

        countdownTask = Task { [weak self] in
            guard let self else { return }
            while self.remainingSeconds > 0 {
                try? await Task.sleep(for: .seconds(1))
                guard !Task.isCancelled else { return }
                self.remainingSeconds -= 1
                self.engine.updateCountdown(context: self.context, remainingSeconds: self.remainingSeconds)
            }
            self.countdownTask = nil
            self.moveToNextStepIfNeeded()
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
        countdownTask?.cancel()
        countdownTask = nil
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
        countdownTask?.cancel()
        countdownTask = nil
        startIfNeeded()
    }
}
