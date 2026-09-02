import Foundation

typealias FrictionStep = PauseStep

nonisolated enum FrictionCategory: String, Codable, CaseIterable, Identifiable, Hashable {
    case games
    case calculations
    case intentions
    case personal

    var id: String { rawValue }

    var title: String {
        switch self {
        case .games:
            "Games"
        case .calculations:
            "Calculations"
        case .intentions:
            "Intentions"
        case .personal:
            "Personal"
        }
    }
}

nonisolated enum FrictionKind: String, Codable, CaseIterable, Identifiable, Hashable {
    case wordSearch
    case letterMatch
    case operations
    case intentionTemplate
    case customIntention
    case personalVideo
    case personalText
    case nfcTag
    case location
    case steps

    var id: String { rawValue }
}

nonisolated struct Friction: Codable, Hashable, Identifiable {
    let id: UUID
    var name: String
    var isEnabled: Bool
    var steps: [FrictionStep]
    var allowanceDuration: TimeInterval
    var relockAfterAllowance: Bool
    /// How long the breathe that opens this friction runs. A setting, not a step -- every
    /// flow opens on one, so a step could only ever add a second copy of it.
    var breatheSeconds: Int
    var createdAt: Date
    var updatedAt: Date

    init(
        id: UUID = UUID(),
        name: String,
        isEnabled: Bool = true,
        steps: [FrictionStep] = [],
        allowanceDuration: TimeInterval = 5 * 60,
        relockAfterAllowance: Bool = true,
        breatheSeconds: Int = LocktyBreathe.minimumSeconds,
        createdAt: Date = Date(),
        updatedAt: Date = Date()
    ) {
        self.id = id
        self.name = name
        self.isEnabled = isEnabled
        self.steps = steps
        self.allowanceDuration = allowanceDuration
        self.relockAfterAllowance = relockAfterAllowance
        self.breatheSeconds = LocktyBreathe.clamped(breatheSeconds)
        self.createdAt = createdAt
        self.updatedAt = updatedAt
    }

    init(flow: PauseFlow) {
        id = flow.id
        name = flow.name
        isEnabled = flow.isEnabled
        steps = flow.steps
        allowanceDuration = flow.allowanceDuration
        relockAfterAllowance = flow.relockAfterAllowance
        breatheSeconds = flow.breatheSeconds
        createdAt = flow.createdAt
        updatedAt = flow.updatedAt
    }

    var flow: PauseFlow {
        PauseFlow(
            id: id,
            name: name,
            icon: icon,
            isEnabled: isEnabled,
            steps: steps,
            allowanceDuration: allowanceDuration,
            relockAfterAllowance: relockAfterAllowance,
            breatheSeconds: breatheSeconds,
            createdAt: createdAt,
            updatedAt: updatedAt
        )
    }

    var summary: String {
        steps.map(\.title).joined(separator: " · ")
    }

    var icon: String? {
        steps.lazy.compactMap { $0.symbolName }.first
    }
}

nonisolated struct FrictionEditorDraft: Codable, Hashable {
    var id: UUID
    var name: String
    var isEnabled: Bool
    var steps: [FrictionStep]
    var allowanceMinutes: Int
    var relockAfterAllowance: Bool
    var breatheSeconds: Int

    init(
        id: UUID = UUID(),
        name: String = "",
        isEnabled: Bool = true,
        steps: [FrictionStep] = [],
        allowanceMinutes: Int = 5,
        relockAfterAllowance: Bool = true,
        breatheSeconds: Int = LocktyBreathe.minimumSeconds
    ) {
        self.id = id
        self.name = name
        self.isEnabled = isEnabled
        self.steps = steps
        self.allowanceMinutes = allowanceMinutes
        self.relockAfterAllowance = relockAfterAllowance
        self.breatheSeconds = LocktyBreathe.clamped(breatheSeconds)
    }

    init(friction: Friction) {
        id = friction.id
        name = friction.name
        isEnabled = friction.isEnabled
        steps = friction.steps
        allowanceMinutes = max(Int(friction.allowanceDuration / 60), 1)
        relockAfterAllowance = friction.relockAfterAllowance
        breatheSeconds = friction.breatheSeconds
    }

    func makeFriction(createdAt: Date, updatedAt: Date) -> Friction {
        Friction(
            id: id,
            name: name.trimmingCharacters(in: .whitespacesAndNewlines),
            isEnabled: isEnabled,
            steps: steps,
            allowanceDuration: TimeInterval(max(allowanceMinutes, 1) * 60),
            relockAfterAllowance: relockAfterAllowance,
            breatheSeconds: breatheSeconds,
            createdAt: createdAt,
            updatedAt: updatedAt
        )
    }
}

nonisolated enum FrictionCompletionResult: String, Codable, CaseIterable, Hashable, Identifiable {
    case completed
    case abandoned
    case interrupted
    case failed

    var id: String { rawValue }
}

nonisolated struct FrictionStepResult: Codable, Hashable, Identifiable {
    let id: UUID
    var title: String
    var startedAt: Date
    var completedAt: Date?
    var isSuccessful: Bool
    var submittedIntentionText: String?
    var chosenPersonalPhrase: String?
    var nfcMatchResult: Bool?

    init(
        id: UUID = UUID(),
        title: String,
        startedAt: Date,
        completedAt: Date? = nil,
        isSuccessful: Bool = false,
        submittedIntentionText: String? = nil,
        chosenPersonalPhrase: String? = nil,
        nfcMatchResult: Bool? = nil
    ) {
        self.id = id
        self.title = title
        self.startedAt = startedAt
        self.completedAt = completedAt
        self.isSuccessful = isSuccessful
        self.submittedIntentionText = submittedIntentionText
        self.chosenPersonalPhrase = chosenPersonalPhrase
        self.nfcMatchResult = nfcMatchResult
    }
}

nonisolated struct FrictionEvent: Codable, Hashable, Identifiable {
    let id: UUID
    var frictionID: UUID
    var startedAt: Date
    var completedAt: Date?
    var result: FrictionCompletionResult
    var stepResults: [FrictionStepResult]
    var submittedIntentionText: String?
    var chosenPersonalPhrase: String?
    var nfcMatchResult: Bool?
    var duration: TimeInterval?

    init(
        id: UUID = UUID(),
        frictionID: UUID,
        startedAt: Date,
        completedAt: Date? = nil,
        result: FrictionCompletionResult,
        stepResults: [FrictionStepResult],
        submittedIntentionText: String? = nil,
        chosenPersonalPhrase: String? = nil,
        nfcMatchResult: Bool? = nil,
        duration: TimeInterval? = nil
    ) {
        self.id = id
        self.frictionID = frictionID
        self.startedAt = startedAt
        self.completedAt = completedAt
        self.result = result
        self.stepResults = stepResults
        self.submittedIntentionText = submittedIntentionText
        self.chosenPersonalPhrase = chosenPersonalPhrase
        self.nfcMatchResult = nfcMatchResult
        self.duration = duration
    }
}

extension PauseStep {
    nonisolated var frictionKind: FrictionKind? {
        switch self {
        case .wordSearch:
            .wordSearch
        case .letterMatch:
            .letterMatch
        case .operations:
            .operations
        case .intentionTemplate:
            .intentionTemplate
        case .customIntention:
            .customIntention
        case .personalVideo:
            .personalVideo
        case .personalText:
            .personalText
        case .nfcTag:
            .nfcTag
        case .location:
            .location
        case .steps:
            .steps
        case .countdown, .breathing, .intention, .confirmation:
            nil
        }
    }

    nonisolated var symbolName: String? {
        switch self {
        case .countdown:
            "timer"
        case .breathing:
            "wind"
        case .wordSearch:
            "textformat.abc.dottedunderline"
        case .letterMatch:
            "point.3.connected.trianglepath.dotted"
        case .operations:
            "plus.forwardslash.minus"
        case .intentionTemplate, .customIntention, .intention:
            "text.bubble"
        case .confirmation:
            "checkmark.circle"
        case .personalVideo:
            "play.rectangle"
        case .personalText:
            "quote.bubble"
        case .nfcTag:
            "wave.3.right.circle"
        case .location:
            "location"
        case .steps:
            "figure.walk"
        }
    }
}

nonisolated enum WordSearchDifficulty: String, Codable, CaseIterable, Hashable, Identifiable {
    case easy
    case medium
    case hard

    var id: String { rawValue }

    var label: String {
        rawValue.capitalized
    }

    var gridSize: Int {
        switch self {
        case .easy:
            6
        case .medium:
            7
        case .hard:
            8
        }
    }
}

nonisolated struct WordSearchConfiguration: Codable, Hashable, Identifiable {
    let id: UUID
    var difficulty: WordSearchDifficulty
    var targetWord: String?

    init(id: UUID = UUID(), difficulty: WordSearchDifficulty = .medium, targetWord: String? = nil) {
        self.id = id
        self.difficulty = difficulty
        self.targetWord = targetWord
    }
}

nonisolated struct WordSearchRuntimeState: Hashable {
    var board: [[Character]]
    var targetWord: String
}

nonisolated struct LetterMatchConfiguration: Codable, Hashable, Identifiable {
    let id: UUID
    var pairCount: Int

    init(id: UUID = UUID(), pairCount: Int = 4) {
        self.id = id
        self.pairCount = pairCount
    }
}

nonisolated struct LetterMatchRuntimeState: Hashable {
    var pairs: [LetterMatchPair]
}

nonisolated struct LetterMatchPair: Hashable, Identifiable {
    let id: UUID
    var letter: String
    var colorName: String
    var startIndex: Int
    var endIndex: Int

    init(
        id: UUID = UUID(),
        letter: String,
        colorName: String,
        startIndex: Int,
        endIndex: Int
    ) {
        self.id = id
        self.letter = letter
        self.colorName = colorName
        self.startIndex = startIndex
        self.endIndex = endIndex
    }
}

nonisolated enum OperationsDifficulty: String, Codable, CaseIterable, Hashable, Identifiable {
    case easy
    case medium
    case hard

    var id: String { rawValue }
}

nonisolated enum ArithmeticOperator: String, Codable, CaseIterable, Hashable, Identifiable {
    case addition = "+"
    case subtraction = "-"
    case multiplication = "×"
    case division = "÷"

    var id: String { rawValue }
}

nonisolated struct OperationsConfiguration: Codable, Hashable, Identifiable {
    let id: UUID
    var difficulty: OperationsDifficulty
    var problemCount: Int
    var allowedOperators: Set<ArithmeticOperator>

    init(
        id: UUID = UUID(),
        difficulty: OperationsDifficulty = .medium,
        problemCount: Int = 3,
        allowedOperators: Set<ArithmeticOperator> = [.addition, .subtraction]
    ) {
        self.id = id
        self.difficulty = difficulty
        self.problemCount = problemCount
        self.allowedOperators = allowedOperators
    }
}

nonisolated struct ArithmeticProblem: Hashable, Identifiable {
    let id: UUID
    var left: Int
    var right: Int
    var operation: ArithmeticOperator
    var answer: Int

    init(id: UUID = UUID(), left: Int, right: Int, operation: ArithmeticOperator, answer: Int) {
        self.id = id
        self.left = left
        self.right = right
        self.operation = operation
        self.answer = answer
    }
}

nonisolated struct OperationsRuntimeState: Hashable {
    var problems: [ArithmeticProblem]
}

nonisolated struct PersonalVideoConfiguration: Codable, Hashable, Identifiable {
    let id: UUID
    var videoFileName: String
    var displayName: String?

    init(id: UUID = UUID(), videoFileName: String, displayName: String? = nil) {
        self.id = id
        self.videoFileName = videoFileName
        self.displayName = displayName
    }
}

nonisolated struct PersonalTextConfiguration: Codable, Hashable, Identifiable {
    let id: UUID
    var phrases: [String]

    init(id: UUID = UUID(), phrases: [String]) {
        self.id = id
        self.phrases = phrases
    }
}

nonisolated struct NFCTagConfiguration: Codable, Hashable, Identifiable {
    let id: UUID
    var normalizedIdentifier: String
    var displayName: String?

    init(id: UUID = UUID(), normalizedIdentifier: String, displayName: String? = nil) {
        self.id = id
        self.normalizedIdentifier = normalizedIdentifier
        self.displayName = displayName
    }
}

extension Friction {
    /// The policy a running session applies when it uses this friction.
    ///
    /// The same conversion `PauseFlow` makes, because the two carry the same four
    /// answers: what you go through, how long it buys, whether it relocks, and how long
    /// the breathe at the front runs.
    var policy: RoutinePausePolicy {
        RoutinePausePolicy(
            isEnabled: isEnabled,
            steps: steps,
            allowanceDuration: allowanceDuration,
            relockAfterAllowance: relockAfterAllowance,
            breatheSeconds: breatheSeconds
        )
    }
}

