import FamilyControls
import ManagedSettings
import SwiftUI

/// Choosing what to unlock and for how long.
///
/// The duration is the flow: it opens on "For..." with the app already decided. The
/// app picker is not a step you walk through, it is what the chip in the top right
/// opens -- so changing your mind costs one tap and agreeing costs none.
struct UnlockFlowView: View {
    let tokens: [ApplicationToken]
    /// Preselected when the flow was opened from a specific app.
    var initialToken: ApplicationToken?
    let configuredSteps: [PauseStep]
    /// How long the opening breathe runs, from the friction's own setting.
    let breatheSeconds: Int
    let allowanceRange: ClosedRange<Int>
    let nfcService: NFCServicing?
    let locationService: LocationTriggerServicing?
    let healthService: HealthServicing?
    let onUnlock: (ApplicationToken?, Int, String?) -> Void
    let onClose: () -> Void

    private enum Step: Hashable {
        case rest
        case app
        case friction(Int)
        case duration
    }

    @State private var step: Step = .rest
    @State private var selectedOptionID: String?
    @State private var minutes: Int?
    @State private var returnStep: Step = .rest
    @State private var currentStepStatus = UnlockFlowStepStatus.ready
    @State private var operationsSubmitTrigger = 0
    @State private var nfcScanTrigger = 0
    @State private var locationCheckTrigger = 0

    init(
        tokens: [ApplicationToken],
        initialToken: ApplicationToken? = nil,
        frictionSteps: [PauseStep] = [],
        breatheSeconds: Int = LocktyBreathe.minimumSeconds,
        allowanceRange: ClosedRange<Int> = 1...15,
        defaultMinutes: Int = 5,
        nfcService: NFCServicing? = nil,
        locationService: LocationTriggerServicing? = nil,
        healthService: HealthServicing? = nil,
        onUnlock: @escaping (ApplicationToken?, Int, String?) -> Void,
        onClose: @escaping () -> Void
    ) {
        self.tokens = tokens
        self.initialToken = initialToken
        self.configuredSteps = frictionSteps
        self.breatheSeconds = LocktyBreathe.clamped(breatheSeconds)
        self.allowanceRange = allowanceRange
        self.nfcService = nfcService
        self.locationService = locationService
        self.healthService = healthService
        self.onUnlock = onUnlock
        self.onClose = onClose
        // Falls back to the first blocked app rather than to nothing: the flow always
        // has an answer for what it is about to unlock.
        let preselected = initialToken ?? tokens.first
        _selectedOptionID = State(initialValue: preselected.map(Self.optionID(for:)))
        _minutes = State(
            initialValue: min(max(defaultMinutes, allowanceRange.lowerBound), allowanceRange.upperBound)
        )
    }

    /// The steps the flow actually walks through.
    ///
    /// Breathing is not among them, and is no longer a step anyone can add: the flow
    /// always opens on a breathe, so one in the list could be added twice, dragged after
    /// a puzzle, or left out of a flow that opens with one regardless. Its length is a
    /// setting on the friction instead. Old flows may still carry the step, which is why
    /// it is filtered rather than assumed gone.
    private var frictionSteps: [PauseStep] {
        configuredSteps.filter {
            if case .breathing = $0 { return false }
            return true
        }
    }

    private static let allAppsOptionID = "all"

    nonisolated private static func optionID(for token: ApplicationToken) -> String {
        AppIdentity.ID(token: token).rawValue
    }

    private var optionIDs: [String] {
        [Self.allAppsOptionID] + tokens.map(Self.optionID(for:))
    }

    private func token(forOptionID id: String) -> ApplicationToken? {
        guard id != Self.allAppsOptionID else { return nil }
        return tokens.first { Self.optionID(for: $0) == id }
    }

    private var selectedToken: ApplicationToken? {
        selectedOptionID.flatMap(token(forOptionID:))
    }

    private var title: String {
        switch step {
        case .rest:
            // The ring is the whole screen. A word over it only names what it is doing.
            return ""
        case .app:
            return "I want to use..."
        case .friction:
            // No titles over the friction steps either. Each one is already a picture of
            // what it is asking for, and the word above it only labelled the obvious --
            // the puzzles had dropped theirs for that reason and the rest had not.
            return ""
        case .duration:
            return "For..."
        }
    }

    private var primaryTitle: String {
        switch step {
        case .app:
            "Done"
        case .duration:
            "Unlock"
        case .friction:
            currentStepStatus.primaryState.title
        default:
            "Continuar"
        }
    }

    private var currentFrictionStep: PauseStep? {
        guard case .friction(let index) = step, frictionSteps.indices.contains(index) else { return nil }
        return frictionSteps[index]
    }

    private var restSeconds: Int {
        switch step {
        case .rest:
            return breatheSeconds
        case .friction(let index):
            guard frictionSteps.indices.contains(index) else { return 0 }
            switch frictionSteps[index] {
            case .countdown(let configuration):
                return Int(configuration.duration)
            case .breathing(let configuration):
                return max(configuration.breathCount * 4, 1)
            default:
                return 0
            }
        default:
            return 0
        }
    }

    private var isPrimaryEnabled: Bool {
        switch step {
        case .friction:
            return currentStepStatus.primaryState.isEnabled
        default:
            return true
        }
    }

    private var capturedIntention: String? {
        let trimmed = currentStepStatus.intentionText?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        return trimmed.isEmpty ? nil : trimmed
    }

    private var nextMainStepAfterRest: Step {
        frictionSteps.isEmpty ? .duration : .friction(0)
    }

    private func advanceFromFriction(at index: Int) {
        // Kept as it is written, so the "past answers" step has something to hand back.
        // Nothing else reads it, and the store keeps only the last twenty.
        if let answer = currentStepStatus.intentionText {
            AppGroupStore().appendIntentionAnswer(answer)
        }

        let nextIndex = frictionSteps.index(after: index)
        withAnimation(.smooth(duration: 0.34)) {
            step = frictionSteps.indices.contains(nextIndex) ? .friction(nextIndex) : .duration
        }
    }

    var body: some View {
        LocktyFlowScreen(
            title: title,
            stepID: step,
            primaryTitle: primaryTitle,
            secondaryTitle: "Leave it",
            isPrimaryEnabled: isPrimaryEnabled,
            restSeconds: restSeconds,
            accessoryToken: step == .app ? nil : selectedToken,
            onAccessory: {
                returnStep = step
                withAnimation(.smooth(duration: 0.34)) { step = .app }
            },
            onClose: onClose,
            onPrimary: {
                switch step {
                case .rest:
                    withAnimation(.smooth(duration: 0.34)) { step = nextMainStepAfterRest }
                case .app:
                    withAnimation(.smooth(duration: 0.34)) { step = returnStep }
                case .friction(let index):
                    handlePrimaryActionForFriction(at: index)
                case .duration:
                    onUnlock(selectedToken, minutes ?? allowanceRange.lowerBound, capturedIntention)
                }
            },
            onSecondary: onClose
        ) {
            switch step {
            case .rest:
                BreathingRest()

            case .app:
                LocktyWheelPicker(items: optionIDs, selection: $selectedOptionID) { id in
                    appRow(id)
                }

            case .friction(let index):
                frictionContent(frictionSteps[index])

            case .duration:
                LocktyWheelPicker(items: Array(allowanceRange), selection: $minutes) { value in
                    Text(value == 1 ? "1 minute" : "\(value) minutes")
                        .font(.system(.title3, design: .default, weight: value == minutes ? .semibold : .regular))
                        .foregroundStyle(LocktyColors.primaryText)
                        .frame(maxWidth: .infinity)
                }
            }
        }
        .onChange(of: step, initial: true) { _, newValue in
            resetCurrentStepStatus(for: newValue)
        }
    }

    @ViewBuilder
    private func frictionContent(_ frictionStep: PauseStep) -> some View {
        switch frictionStep {
        case .countdown:
            // The glyph, and nothing written under it. The seconds are already running
            // down inside the primary button -- the label here was the configured length
            // rather than what is left, so it sat there contradicting the live number.
            UnlockStepSurface(tone: .neutral, shakeTrigger: 0) {
                Image(systemName: "timer")
                    .font(.system(size: 40, weight: .light))
                    .foregroundStyle(LocktyColors.primaryText)
                    .frame(maxWidth: .infinity)
            }

        case .breathing:
            // Filtered out of `frictionSteps`: it is the opening breathe's duration, not
            // a screen. Unreachable, and here only because the switch is exhaustive.
            EmptyView()

        case .intention(let configuration),
             .intentionTemplate(let configuration),
             .customIntention(let configuration):
            UnlockIntentionStepView(configuration: configuration, status: $currentStepStatus)

        case .confirmation(let configuration):
            UnlockConfirmationStepView(configuration: configuration)

        case .personalText(let configuration):
            UnlockPersonalTextStepView(configuration: configuration, status: $currentStepStatus)

        case .copyPhrase(let configuration):
            UnlockCopyPhraseStepView(configuration: configuration, status: $currentStepStatus)

        case .holdSteady(let configuration):
            UnlockHoldSteadyStepView(configuration: configuration, status: $currentStepStatus)

        case .oddOneOut(let configuration):
            UnlockOddOneOutStepView(configuration: configuration, status: $currentStepStatus)

        case .sortNumbers(let configuration):
            UnlockSortNumbersStepView(configuration: configuration, status: $currentStepStatus)

        case .pastAnswers(let configuration):
            UnlockPastAnswersStepView(configuration: configuration, status: $currentStepStatus)

        case .tuneValue(let configuration):
            UnlockTuneValueStepView(configuration: configuration, status: $currentStepStatus)

        case .wordSearch(let configuration):
            UnlockWordSearchStepView(configuration: configuration, status: $currentStepStatus)

        case .letterMatch(let configuration):
            UnlockLetterMatchStepView(configuration: configuration, status: $currentStepStatus)

        case .operations(let configuration):
            UnlockOperationsStepView(
                configuration: configuration,
                submitTrigger: operationsSubmitTrigger,
                status: $currentStepStatus
            )

        case .personalVideo(let configuration):
            UnlockPersonalVideoStepView(configuration: configuration, status: $currentStepStatus)

        case .nfcTag(let configuration):
            UnlockNFCTagStepView(
                configuration: configuration,
                scanTrigger: nfcScanTrigger,
                nfcService: nfcService,
                status: $currentStepStatus
            )

        case .steps(let configuration):
            UnlockStepsStepView(
                configuration: configuration,
                healthService: healthService,
                status: $currentStepStatus
            )

        case .location(let configuration):
            UnlockLocationStepView(
                configuration: configuration,
                checkTrigger: locationCheckTrigger,
                locationService: locationService,
                status: $currentStepStatus
            )
        }
    }

    private func handlePrimaryActionForFriction(at index: Int) {
        guard frictionSteps.indices.contains(index) else { return }

        switch frictionSteps[index] {
        case .operations:
            switch currentStepStatus.primaryState {
            case .advance:
                advanceFromFriction(at: index)
            case .submit(let enabled):
                guard enabled else { return }
                operationsSubmitTrigger += 1
            case .scan:
                advanceFromFriction(at: index)
            }

        case .nfcTag:
            switch currentStepStatus.primaryState {
            case .advance:
                advanceFromFriction(at: index)
            case .scan(let enabled):
                guard enabled else { return }
                nfcScanTrigger += 1
            case .submit:
                advanceFromFriction(at: index)
            }

        case .location:
            switch currentStepStatus.primaryState {
            case .advance:
                advanceFromFriction(at: index)
            case .submit(let enabled):
                guard enabled else { return }
                locationCheckTrigger += 1
            case .scan:
                advanceFromFriction(at: index)
            }

        default:
            advanceFromFriction(at: index)
        }
    }

    private func resetCurrentStepStatus(for step: Step) {
        switch step {
        case .friction(let index):
            guard frictionSteps.indices.contains(index) else {
                currentStepStatus = .ready
                return
            }

            switch frictionSteps[index] {
            case .wordSearch, .letterMatch, .personalVideo:
                currentStepStatus = UnlockFlowStepStatus(primaryState: .advance(enabled: false))
            case .operations:
                currentStepStatus = UnlockFlowStepStatus(primaryState: .submit(enabled: false))
            case .nfcTag:
                currentStepStatus = UnlockFlowStepStatus(primaryState: .scan(enabled: true))
            case .location:
                currentStepStatus = UnlockFlowStepStatus(primaryState: .submit(enabled: true))
            case .intention, .intentionTemplate, .customIntention:
                currentStepStatus = UnlockFlowStepStatus(primaryState: .advance(enabled: false), intentionText: nil)
            default:
                currentStepStatus = .ready
            }
        default:
            currentStepStatus = .ready
        }
    }

    /// A row is exactly as tall as the wheel's row: the icon is sized to sit inside it,
    /// not to set it. Sizing the icon first is what made these rows enormous.
    @ViewBuilder
    private func appRow(_ id: String) -> some View {
        HStack(spacing: LocktySpacing.md) {
            if let token = token(forOptionID: id) {
                Label(token)
                    .labelStyle(.iconOnly)
                    .id(token)
                    .frame(width: 34, height: 34)

                // The token is the only thing carrying the app's real name.
                Label(token)
                    .labelStyle(.titleOnly)
                    .font(.system(.title3, design: .default, weight: .regular))
                    .foregroundStyle(LocktyColors.primaryText)
                    .lineLimit(1)
            } else {
                Image(systemName: "iphone")
                    .font(.system(size: 17, weight: .regular))
                    .foregroundStyle(LocktyColors.primaryText)
                    .frame(width: 34, height: 34)
                    .background(
                        RoundedRectangle(cornerRadius: 9, style: .continuous)
                            .fill(LocktyColors.elevatedBackground)
                    )

                Text("All apps")
                    .font(.system(.title3, design: .default, weight: .regular))
                    .foregroundStyle(LocktyColors.primaryText)
                    .lineLimit(1)
            }

            Spacer(minLength: 0)
        }
        .padding(.horizontal, LocktySpacing.lg)
    }
}


/// What the rest step shows: a ring that breathes in and out on its own.
///
/// Nothing to read and nothing to answer -- the point of the step is that there is
/// nothing to do in it, so it holds one slow, obvious rhythm to follow instead.
private struct BreathingRest: View {
    @State private var isExpanded = false

    var body: some View {
        ZStack {
            ForEach(0..<3, id: \.self) { index in
                Circle()
                    .stroke(
                        LocktyColors.primaryText.opacity(0.10 - Double(index) * 0.025),
                        lineWidth: 1
                    )
                    .frame(width: 150 + CGFloat(index) * 46)
                    .scaleEffect(isExpanded ? 1.08 : 0.94)
            }

            Circle()
                .fill(LocktyColors.primaryText.opacity(0.06))
                .frame(width: 150)
                .scaleEffect(isExpanded ? 1.12 : 0.9)
        }
        .frame(height: 260)
        .animation(.easeInOut(duration: 2.4).repeatForever(autoreverses: true), value: isExpanded)
        .onAppear { isExpanded = true }
    }
}
