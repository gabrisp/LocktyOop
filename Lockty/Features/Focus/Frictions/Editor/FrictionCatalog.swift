import SwiftUI

struct FrictionCatalogItem: Identifiable {
    let id: String
    let kind: FrictionKind
    let category: FrictionCategory
    let title: String
    let subtitle: String
    let systemImage: String
    let tint: Color
    let makeStep: () -> FrictionStep

    init(
        kind: FrictionKind,
        category: FrictionCategory,
        title: String,
        subtitle: String,
        systemImage: String,
        tint: Color,
        makeStep: @escaping () -> FrictionStep
    ) {
        self.id = "\(category.rawValue)-\(kind.rawValue)-\(title)"
        self.kind = kind
        self.category = category
        self.title = title
        self.subtitle = subtitle
        self.systemImage = systemImage
        self.tint = tint
        self.makeStep = makeStep
    }
}

enum FrictionCatalog {
    static let items: [FrictionCatalogItem] = [
        FrictionCatalogItem(
            kind: .wordSearch,
            category: .games,
            title: "Word Search",
            subtitle: "Find the target word in a clean grid.",
            systemImage: "textformat.abc.dottedunderline",
            tint: .blue
        ) {
            .wordSearch(WordSearchConfiguration())
        },
        FrictionCatalogItem(
            kind: .letterMatch,
            category: .games,
            title: "Letter Match",
            subtitle: "Connect every matching pair without crossing.",
            systemImage: "point.3.connected.trianglepath.dotted",
            tint: .mint
        ) {
            .letterMatch(LetterMatchConfiguration())
        },
        FrictionCatalogItem(
            kind: .operations,
            category: .calculations,
            title: "Operations",
            subtitle: "Solve a configured set of arithmetic prompts.",
            systemImage: "plus.forwardslash.minus",
            tint: .orange
        ) {
            .operations(OperationsConfiguration())
        },
        FrictionCatalogItem(
            kind: .intentionTemplate,
            category: .intentions,
            title: "Name the Why",
            subtitle: "Require a short intention before unlocking.",
            systemImage: "text.bubble",
            tint: .pink
        ) {
            .intentionTemplate(
                IntentionConfiguration(
                    prompt: "Why are you opening this app right now?",
                    minimumLength: 18,
                    isRequired: true
                )
            )
        },
        FrictionCatalogItem(
            kind: .intentionTemplate,
            category: .intentions,
            title: "Check the Intent",
            subtitle: "Ask for the concrete action the user wants to take.",
            systemImage: "checklist",
            tint: .indigo
        ) {
            .intentionTemplate(
                IntentionConfiguration(
                    prompt: "What exactly will you do once the app opens?",
                    minimumLength: 20,
                    isRequired: true
                )
            )
        },
        FrictionCatalogItem(
            kind: .customIntention,
            category: .intentions,
            title: "Custom Intention",
            subtitle: "Write your own prompt and minimum length.",
            systemImage: "pencil.and.scribble",
            tint: .purple
        ) {
            .customIntention(
                IntentionConfiguration(
                    prompt: "Describe the intention you want to enforce.",
                    minimumLength: 24,
                    isRequired: true
                )
            )
        },
        FrictionCatalogItem(
            kind: .personalText,
            category: .personal,
            title: "Personal Text",
            subtitle: "Show one saved phrase for the current run.",
            systemImage: "quote.bubble",
            tint: .teal
        ) {
            .personalText(PersonalTextConfiguration(phrases: ["Remember what you came here for."]))
        },
        FrictionCatalogItem(
            kind: .personalVideo,
            category: .personal,
            title: "Personal Video",
            subtitle: "Play a saved video from your library before unlocking.",
            systemImage: "play.rectangle",
            tint: .red
        ) {
            .personalVideo(PersonalVideoConfiguration(videoFileName: "", displayName: nil))
        },
        FrictionCatalogItem(
            kind: .nfcTag,
            category: .personal,
            title: "NFC Tag",
            subtitle: "Require the saved physical tag to continue.",
            systemImage: "wave.3.right.circle",
            tint: .cyan
        ) {
            .nfcTag(NFCTagConfiguration(normalizedIdentifier: "", displayName: nil))
        },
        FrictionCatalogItem(
            kind: .location,
            category: .personal,
            title: "Location",
            subtitle: "Only continue when you are inside the saved place.",
            systemImage: "location",
            tint: .green
        ) {
            .location(LocationTrigger(name: "", latitude: 0, longitude: 0, radiusMeters: 150, startsOnEntry: true))
        },
        FrictionCatalogItem(
            kind: .steps,
            category: .personal,
            title: "Steps",
            subtitle: "Only continue once you have walked today's goal.",
            systemImage: "figure.walk",
            tint: .orange
        ) {
            .steps(StepsConfiguration())
        }
    ]

    static func items(in category: FrictionCategory) -> [FrictionCatalogItem] {
        items.filter { $0.category == category }
    }
}
