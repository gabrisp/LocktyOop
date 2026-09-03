import Foundation

nonisolated struct PauseRule: Codable, Hashable, Identifiable {
    let id: UUID
    var application: AppIdentity
    /// User-supplied label. The system only hands us an opaque token for a selected
    /// app, so its real name isn't ours to read — this is what lets a Pause be
    /// identifiable in our own UI.
    var customName: String?
    var isEnabled: Bool
    var steps: [PauseStep]
    var allowanceDuration: TimeInterval
    var relockAfterAllowance: Bool
    var createdAt: Date
    var updatedAt: Date

    /// What to show for this Pause: the user's label when they gave one.
    var displayName: String {
        let trimmed = customName?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        return trimmed.isEmpty ? application.displayName : trimmed
    }

    init(
        id: UUID = UUID(),
        application: AppIdentity,
        customName: String? = nil,
        isEnabled: Bool,
        steps: [PauseStep],
        allowanceDuration: TimeInterval,
        relockAfterAllowance: Bool = true,
        createdAt: Date = Date(),
        updatedAt: Date = Date()
    ) {
        self.id = id
        self.application = application
        self.customName = customName
        self.isEnabled = isEnabled
        self.steps = steps
        self.allowanceDuration = allowanceDuration
        self.relockAfterAllowance = relockAfterAllowance
        self.createdAt = createdAt
        self.updatedAt = updatedAt
    }
}

nonisolated enum PauseStep: Codable, Hashable, Identifiable {
    case countdown(CountdownConfiguration)
    case breathing(BreathingConfiguration)
    case wordSearch(WordSearchConfiguration)
    case letterMatch(LetterMatchConfiguration)
    case operations(OperationsConfiguration)
    case intentionTemplate(IntentionConfiguration)
    case customIntention(IntentionConfiguration)
    case intention(IntentionConfiguration)
    case confirmation(ConfirmationConfiguration)
    case personalVideo(PersonalVideoConfiguration)
    case personalText(PersonalTextConfiguration)
    case nfcTag(NFCTagConfiguration)
    case location(LocationTrigger)
    case steps(StepsConfiguration)
    case copyPhrase(CopyPhraseConfiguration)
    case holdSteady(HoldSteadyConfiguration)
    case oddOneOut(OddOneOutConfiguration)
    case sortNumbers(SortNumbersConfiguration)
    case pastAnswers(PastAnswersConfiguration)
    case tuneValue(TuneValueConfiguration)

    var id: UUID {
        switch self {
        case .countdown(let configuration):
            configuration.id
        case .breathing(let configuration):
            configuration.id
        case .wordSearch(let configuration):
            configuration.id
        case .letterMatch(let configuration):
            configuration.id
        case .operations(let configuration):
            configuration.id
        case .intentionTemplate(let configuration):
            configuration.id
        case .customIntention(let configuration):
            configuration.id
        case .intention(let configuration):
            configuration.id
        case .confirmation(let configuration):
            configuration.id
        case .personalVideo(let configuration):
            configuration.id
        case .personalText(let configuration):
            configuration.id
        case .nfcTag(let configuration):
            configuration.id
        case .location(let configuration):
            configuration.id
        case .steps(let configuration):
            configuration.id
        case .copyPhrase(let configuration):
            configuration.id
        case .holdSteady(let configuration):
            configuration.id
        case .oddOneOut(let configuration):
            configuration.id
        case .sortNumbers(let configuration):
            configuration.id
        case .pastAnswers(let configuration):
            configuration.id
        case .tuneValue(let configuration):
            configuration.id
        }
    }

    var title: String {
        switch self {
        case .countdown:
            "Countdown"
        case .breathing:
            "Breathe"
        case .wordSearch:
            "Word Search"
        case .letterMatch:
            "Letter Match"
        case .operations:
            "Operations"
        case .intentionTemplate:
            "Intention"
        case .customIntention:
            "Custom Intention"
        case .intention:
            "Write intention"
        case .confirmation:
            "Confirm"
        case .personalVideo:
            "Personal Video"
        case .personalText:
            "Personal Text"
        case .nfcTag:
            "NFC Tag"
        case .location:
            "Location"
        case .copyPhrase:
            "Copy the Phrase"
        case .holdSteady:
            "Hold Steady"
        case .oddOneOut:
            "Odd One Out"
        case .sortNumbers:
            "Sort the Numbers"
        case .pastAnswers:
            "Your Past Answers"
        case .tuneValue:
            "Tune the Value"
        case .steps:
            "Steps"
        }
    }

    var detail: String {
        switch self {
        case .countdown(let configuration):
            return "\(Int(configuration.duration)) sec"
        case .breathing(let configuration):
            return "\(configuration.breathCount) breaths"
        case .wordSearch(let configuration):
            return configuration.difficulty.label
        case .letterMatch(let configuration):
            return "\(configuration.pairCount) pairs"
        case .operations(let configuration):
            return "\(configuration.problemCount) problems"
        case .intentionTemplate(let configuration), .customIntention(let configuration), .intention(let configuration):
            if let minimumLength = configuration.minimumLength, minimumLength > 0 {
                return "\(minimumLength)+ chars"
            }
            return "Write briefly"
        case .personalVideo(let configuration):
            return configuration.displayName ?? "Selected clip"
        case .personalText(let configuration):
            return configuration.phrases.count == 1 ? "1 phrase" : "\(configuration.phrases.count) phrases"
        case .nfcTag(let configuration):
            return configuration.displayName ?? "Saved tag"
        case .location(let configuration):
            let label = configuration.name.trimmingCharacters(in: .whitespacesAndNewlines)
            return label.isEmpty ? "\(Int(configuration.radiusMeters)) m radius" : label
        case .confirmation:
            return "Deliberate choice"
        case .copyPhrase(let configuration):
            return configuration.length.title.lowercased() + " phrase"
        case .holdSteady(let configuration):
            return "\(configuration.seconds)s hold"
        case .oddOneOut(let configuration):
            return configuration.rounds == 1 ? "1 round" : "\(configuration.rounds) rounds"
        case .sortNumbers(let configuration):
            return "\(configuration.count) numbers"
        case .pastAnswers(let configuration):
            return configuration.recallCount == 1 ? "1 answer" : "\(configuration.recallCount) answers"
        case .tuneValue(let configuration):
            return configuration.tolerance == 0 ? "exact" : "±\(configuration.tolerance)"
        case .steps(let configuration):
            return "\(configuration.dailyGoal.formatted(.number.grouping(.automatic))) steps"
        }
    }
}

/// A step goal that has to be met before the unlock is offered.
///
/// The goal is stored, never the count. What has been walked today is read from Health at
/// the moment the step is shown -- storing it would be a number that goes stale between
/// one unlock and the next.
nonisolated struct StepsConfiguration: Codable, Hashable, Identifiable {
    let id: UUID
    var dailyGoal: Int

    init(id: UUID = UUID(), dailyGoal: Int = 8000) {
        self.id = id
        self.dailyGoal = dailyGoal
    }
}

nonisolated struct CountdownConfiguration: Codable, Hashable, Identifiable {
    let id: UUID
    var duration: TimeInterval

    init(id: UUID = UUID(), duration: TimeInterval) {
        self.id = id
        self.duration = duration
    }
}

nonisolated struct BreathingConfiguration: Codable, Hashable, Identifiable {
    let id: UUID
    var breathCount: Int

    init(id: UUID = UUID(), breathCount: Int) {
        self.id = id
        self.breathCount = breathCount
    }
}

nonisolated struct IntentionConfiguration: Codable, Hashable, Identifiable {
    let id: UUID
    var prompt: String
    var minimumLength: Int?
    var isRequired: Bool

    init(
        id: UUID = UUID(),
        prompt: String,
        minimumLength: Int? = nil,
        isRequired: Bool
    ) {
        self.id = id
        self.prompt = prompt
        self.minimumLength = minimumLength
        self.isRequired = isRequired
    }
}

nonisolated struct ConfirmationConfiguration: Codable, Hashable, Identifiable {
    let id: UUID
    var prompt: String

    init(id: UUID = UUID(), prompt: String = "Do you still want to continue?") {
        self.id = id
        self.prompt = prompt
    }
}

nonisolated enum PauseDecision: String, Codable, CaseIterable, Hashable, Identifiable {
    case abandoned
    case continued
    case interrupted

    var id: String { rawValue }
}

nonisolated struct PauseEvent: Codable, Hashable, Identifiable {
    let id: UUID
    var pauseRuleID: UUID
    var application: AppIdentity
    var triggeredAt: Date
    var completedAt: Date?
    var intention: String?
    var decision: PauseDecision
    var allowanceDuration: TimeInterval?
    var actualUsageDuration: TimeInterval?

    init(
        id: UUID = UUID(),
        pauseRuleID: UUID,
        application: AppIdentity,
        triggeredAt: Date,
        completedAt: Date? = nil,
        intention: String? = nil,
        decision: PauseDecision,
        allowanceDuration: TimeInterval? = nil,
        actualUsageDuration: TimeInterval? = nil
    ) {
        self.id = id
        self.pauseRuleID = pauseRuleID
        self.application = application
        self.triggeredAt = triggeredAt
        self.completedAt = completedAt
        self.intention = intention
        self.decision = decision
        self.allowanceDuration = allowanceDuration
        self.actualUsageDuration = actualUsageDuration
    }
}

// Preview/test fixtures only.
#if DEBUG
extension PauseRule {
    static let mockInstagram = PauseRule(
        id: UUID(uuidString: "00000000-0000-0000-0000-000000000701")!,
        application: .mockInstagram,
        isEnabled: true,
        steps: [
            .countdown(CountdownConfiguration(duration: 10)),
            .intention(
                IntentionConfiguration(
                    prompt: "What exactly are you opening Instagram for?",
                    minimumLength: 15,
                    isRequired: true
                )
            ),
            .confirmation(ConfirmationConfiguration())
        ],
        allowanceDuration: 5 * 60
    )

    static let mockTikTok = PauseRule(
        id: UUID(uuidString: "00000000-0000-0000-0000-000000000702")!,
        application: .mockTikTok,
        isEnabled: true,
        steps: [
            .breathing(BreathingConfiguration(breathCount: 3)),
            .countdown(CountdownConfiguration(duration: 15)),
            .intention(
                IntentionConfiguration(
                    prompt: "Name the reason before you continue.",
                    minimumLength: 20,
                    isRequired: true
                )
            ),
            .confirmation(ConfirmationConfiguration())
        ],
        allowanceDuration: 5 * 60
    )

    static let mockX = PauseRule(
        id: UUID(uuidString: "00000000-0000-0000-0000-000000000703")!,
        application: .mockX,
        isEnabled: true,
        steps: [
            .countdown(CountdownConfiguration(duration: 8)),
            .confirmation(ConfirmationConfiguration())
        ],
        allowanceDuration: 3 * 60
    )
}

extension AppIdentity {
    static let mockInstagram = AppIdentity(
        id: "instagram",
        displayName: "Instagram",
        bundleIdentifier: "com.burbn.instagram",
        iconSource: .appStoreArtworkURL("https://is1-ssl.mzstatic.com/image/thumb/Purple221/v4/23/59/e9/2359e92d-376c-cc29-b9e6-ab9a4a00fcf4/Prod-0-0-1x_U007epad-0-1-0-sRGB-85-220.png/512x512bb.jpg")
    )

    static let mockTikTok = AppIdentity(
        id: "tiktok",
        displayName: "TikTok",
        bundleIdentifier: "com.zhiliaoapp.musically",
        iconSource: .appStoreArtworkURL("https://is1-ssl.mzstatic.com/image/thumb/Purple211/v4/b4/f6/9e/b4f69e23-a20c-784c-7f41-400fd8ab3d1c/TikTok_AppIcon26-0-0-1x_U007epad-0-1-0-85-220.png/512x512bb.jpg")
    )

    static let mockX = AppIdentity(
        id: "x",
        displayName: "X",
        bundleIdentifier: "com.atebits.Tweetie2",
        iconSystemName: "xmark",
        iconSource: .systemImage("xmark")
    )
}
#endif
