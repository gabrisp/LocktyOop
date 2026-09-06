import Foundation

/// One fixed step per catalogue entry, built once.
///
/// The grid used to call `makeStep()` inside each cell's body, which mints a fresh
/// configuration -- and a fresh UUID -- on every redraw. That is a new identity for the
/// preview each time SwiftUI looks at it, so every `task(id:)` inside restarted: boards
/// re-dealt, phrases changed, timers began again. Scrolling the catalogue was rebuilding
/// it continuously.
///
/// These are constants. A preview does not need a unique identity; it needs a stable one.
nonisolated enum FrictionPreviewSteps {
    /// The step to draw for a kind, or nil for the ones with nothing to preview.
    ///
    /// Location is absent on purpose: it has no configuration that means anything without
    /// a place chosen, and a preview of "be somewhere unspecified" says nothing.
    static func step(for kind: FrictionKind) -> FrictionStep? {
        cache[kind]
    }

    private static let cache: [FrictionKind: FrictionStep] = [
        .copyPhrase: .copyPhrase(CopyPhraseConfiguration()),
        .holdSteady: .holdSteady(HoldSteadyConfiguration()),
        .oddOneOut: .oddOneOut(OddOneOutConfiguration()),
        .sortNumbers: .sortNumbers(SortNumbersConfiguration()),
        .tuneValue: .tuneValue(TuneValueConfiguration()),
        .pastAnswers: .pastAnswers(PastAnswersConfiguration()),
        .wordSearch: .wordSearch(WordSearchConfiguration()),
        .letterMatch: .letterMatch(LetterMatchConfiguration()),
        .operations: .operations(OperationsConfiguration()),
        .intentionTemplate: .intention(
            IntentionConfiguration(prompt: "What are you opening this for?", isRequired: true)
        ),
        .customIntention: .intention(
            IntentionConfiguration(prompt: "What are you opening this for?", isRequired: true)
        ),
        .personalVideo: .personalVideo(PersonalVideoConfiguration(videoFileName: "")),
        .personalText: .personalText(
            PersonalTextConfiguration(phrases: ["A note you wrote to yourself."])
        ),
        .nfcTag: .nfcTag(NFCTagConfiguration(normalizedIdentifier: "")),
        .steps: .steps(StepsConfiguration()),
        .objectives: .objectives(ObjectivesFrictionConfiguration())
    ]
}
