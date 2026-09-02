import Foundation

/// A set of things the block screen can say.
///
/// Two kinds live in one list on purpose. Some packs are a list of lines picked from at
/// random; others are computed from the day -- what this app has already cost, the reason
/// you wrote down. They are the same choice from the reader's side ("what should the
/// shield say?"), so they are the same list.
nonisolated struct ShieldScreenPack: Identifiable, Hashable, Sendable {
    enum Source: Hashable, Sendable {
        /// One of `messages`, chosen at random each time the shield is drawn.
        case messages
        /// How long this app has taken today.
        case cost
        /// The line the person wrote for themselves.
        case intention
        /// Nothing. Selecting this silences every other pack.
        case silence
    }

    let id: String
    let emoji: String
    let title: String
    let subtitle: String
    /// Marked in the list. Nothing is withheld -- there is no paywall in the app yet --
    /// but the badge is where one would go.
    let isPro: Bool
    let source: Source
    let messages: [String]

    init(
        id: String,
        emoji: String,
        title: String,
        subtitle: String,
        isPro: Bool = false,
        source: Source = .messages,
        messages: [String] = []
    ) {
        self.id = id
        self.emoji = emoji
        self.title = title
        self.subtitle = subtitle
        self.isPro = isPro
        self.source = source
        self.messages = messages
    }
}

/// Everything the block screen can be set to say.
///
/// The lines are written for this app rather than collected from elsewhere: quotations
/// are from writers long out of copyright, and the rest is ours. A pack of someone else's
/// product copy would be a licensing problem wearing a feature's clothes.
nonisolated enum ShieldScreenCatalog {
    static let packs: [ShieldScreenPack] = [
        ShieldScreenPack(
            id: "default",
            emoji: "👋",
            title: "Default",
            subtitle: "Lockty says it blocked this app, and nothing more.",
            messages: ["Blocked by Lockty."]
        ),
        ShieldScreenPack(
            id: "cost",
            emoji: "⏳",
            title: "What it costs",
            subtitle: "How long this app has already taken today.",
            source: .cost
        ),
        ShieldScreenPack(
            id: "intention",
            emoji: "✍️",
            title: "Your reason",
            subtitle: "The line you wrote for yourself.",
            source: .intention
        ),
        ShieldScreenPack(
            id: "offline",
            emoji: "💡",
            title: "Offline ideas",
            subtitle: "Small things to do without the phone.",
            messages: [
                "Make the coffee properly. Watch it drip.",
                "Write down the thing you keep forgetting.",
                "Stand up. Look at something further than two feet away.",
                "Text the person you have been meaning to text.",
                "Ten minutes on the instrument you said you were learning.",
                "Put one thing back where it belongs.",
                "Go outside without headphones."
            ]
        ),
        ShieldScreenPack(
            id: "haiku",
            emoji: "🪶",
            title: "Focus haiku",
            subtitle: "Seventeen syllables, then back to work.",
            messages: [
                "The feed does not end.\nThat is the whole design of it.\nYou can end instead.",
                "Thumb hovers, waiting.\nNothing new has happened since\nthe last time you looked.",
                "You came here for one\nthing and forgot it halfway.\nGo and remember.",
                "A small grey rectangle\nasking for the only hours\nyou will ever have.",
                "The notification\nwill still be there in an hour.\nSo will you. Probably."
            ]
        ),
        ShieldScreenPack(
            id: "luminaries",
            emoji: "🧠",
            title: "Luminaries",
            subtitle: "People who thought about attention before it was sold.",
            messages: [
                "\u{201C}It is not that we have a short time to live, but that we waste a lot of it.\u{201D}\n— Seneca",
                "\u{201C}You could leave life right now. Let that determine what you do and say.\u{201D}\n— Marcus Aurelius",
                "\u{201C}The price of anything is the amount of life you exchange for it.\u{201D}\n— Henry David Thoreau",
                "\u{201C}Beware the barrenness of a busy life.\u{201D}\n— Socrates",
                "\u{201C}How we spend our days is, of course, how we spend our lives.\u{201D}\n— Annie Dillard",
                "\u{201C}All of humanity's problems stem from man's inability to sit quietly in a room alone.\u{201D}\n— Blaise Pascal"
            ]
        ),
        ShieldScreenPack(
            id: "austen",
            emoji: "🎀",
            title: "Jane Austen",
            subtitle: "Politely disappointed in you.",
            isPro: true,
            messages: [
                "\u{201C}To sit in the shade on a fine day and look upon verdure is the most perfect refreshment.\u{201D}",
                "\u{201C}I declare after all there is no enjoyment like reading!\u{201D}",
                "\u{201C}There is no charm equal to tenderness of heart.\u{201D}",
                "\u{201C}One half of the world cannot understand the pleasures of the other.\u{201D}",
                "\u{201C}We have all a better guide in ourselves, if we would attend to it.\u{201D}"
            ]
        ),
        ShieldScreenPack(
            id: "blunt",
            emoji: "😈",
            title: "Blunt",
            subtitle: "No encouragement. Ages 13 and up.",
            isPro: true,
            messages: [
                "You already checked. Nothing changed.",
                "This is the fourth time. Nobody is counting except the app.",
                "You are not looking for anything. You are just looking.",
                "The scroll is not a break. It is the thing you need a break from.",
                "You set this block. Past you was thinking more clearly.",
                "Whatever you were about to do instead, do that."
            ]
        ),
        ShieldScreenPack(
            id: "scripture",
            emoji: "🙏",
            title: "Scripture",
            subtitle: "Lines from the Gospels.",
            isPro: true,
            messages: [
                "\u{201C}Take therefore no thought for the morrow: for the morrow shall take thought for the things of itself.\u{201D}\n— Matthew 6:34",
                "\u{201C}Be still, and know.\u{201D}\n— Psalm 46:10",
                "\u{201C}Where your treasure is, there will your heart be also.\u{201D}\n— Matthew 6:21",
                "\u{201C}Let your yes be yes, and your no be no.\u{201D}\n— Matthew 5:37"
            ]
        ),
        ShieldScreenPack(
            id: "quran",
            emoji: "📿",
            title: "Quranic inspiration",
            subtitle: "Lines on patience and change.",
            isPro: true,
            messages: [
                "\u{201C}Indeed, Allah will not change the condition of a people until they change what is in themselves.\u{201D}\n— 13:11",
                "\u{201C}And be patient. Indeed, Allah is with the patient.\u{201D}\n— 8:46",
                "\u{201C}Indeed, with hardship comes ease.\u{201D}\n— 94:6",
                "\u{201C}And it is He who created the night and the day.\u{201D}\n— 21:33"
            ]
        ),
        ShieldScreenPack(
            id: "space",
            emoji: "🪐",
            title: "Space news",
            subtitle: "The universe, years late.",
            isPro: true,
            messages: [
                "Light leaving Proxima Centauri today arrives in four years. It is in no hurry.",
                "Saturn's rings are younger than the dinosaurs and will be gone before the sun is.",
                "There is a cloud in Sagittarius made largely of alcohol. Nobody can reach it.",
                "A day on Venus is longer than its year.",
                "Every atom heavier than iron in your hand was made in a dying star."
            ]
        ),
        ShieldScreenPack(
            id: "trivia",
            emoji: "🔍",
            title: "Trivia",
            subtitle: "A fact for the trouble.",
            isPro: true,
            messages: [
                "Honey found in Egyptian tombs was still edible after three thousand years.",
                "Octopuses have three hearts, and two of them stop when they swim.",
                "The Eiffel Tower is about 15 cm taller in summer.",
                "Bananas are berries. Strawberries are not.",
                "Wombat droppings are cubes, which is why they do not roll away."
            ]
        ),
        ShieldScreenPack(
            id: "quiet",
            emoji: "🌙",
            title: "Quiet",
            subtitle: "The app's name and the buttons. No message at all.",
            source: .silence
        )
    ]

    static func pack(id: String) -> ShieldScreenPack? {
        packs.first { $0.id == id }
    }

    static let defaultPackID = "default"
}
