import Foundation

/// The words and sentences the frictions draw from.
///
/// Kept here rather than inside the views because the point of them is that there are a
/// lot: a friction you have seen six times is a friction you can finish without reading,
/// and the word search used to have a bank of six.
///
/// Deliberately ordinary words. The old bank was FOCUS, CALM, INTENT, DISCIPLINE -- which
/// made a puzzle into a poster, and a poster you have read is scenery. A friction should
/// cost attention, not deliver a message.
nonisolated enum FrictionWordBank {
    /// Concrete, common, and nothing to do with self-improvement.
    static let words: [String] = [
        "ANCHOR", "BASKET", "BRIDGE", "CANDLE", "CARPET", "CASTLE", "CELLAR", "CIRCUS",
        "COFFEE", "COPPER", "COTTON", "CRAYON", "DESERT", "DINNER", "DONKEY", "ENGINE",
        "FABRIC", "FALCON", "FARMER", "FINGER", "FOREST", "GARDEN", "GRAVEL", "HAMMER",
        "HARBOR", "HELMET", "ISLAND", "JACKET", "JUNGLE", "KETTLE", "LADDER", "LANTERN",
        "LEMON", "MARBLE", "MEADOW", "MIRROR", "MITTEN", "MONKEY", "MUSEUM", "NEEDLE",
        "ORANGE", "OYSTER", "PALACE", "PARCEL", "PEBBLE", "PENCIL", "PEPPER", "PIGEON",
        "PILLOW", "PLANET", "POCKET", "POTATO", "PUDDLE", "RABBIT", "RIBBON", "RIVER",
        "SADDLE", "SALMON", "SANDAL", "SAUCER", "SHOVEL", "SILVER", "SPIDER", "SPOON",
        "STREET", "SUGAR", "SWEATER", "TEAPOT", "THREAD", "TICKET", "TIMBER", "TOMATO",
        "TUNNEL", "TURTLE", "VALLEY", "VELVET", "WAGON", "WALNUT", "WHISTLE", "WILLOW",
        "WINDOW", "WINTER", "YELLOW", "ZEBRA", "ALMOND", "ANCHOVY", "BADGER", "BAMBOO",
        "BEACON", "BEETLE", "BLANKET", "BOTTLE", "BOULDER", "BUCKET", "BUTTON", "CABBAGE",
        "CACTUS", "CAMERA", "CANYON", "CARROT", "CHERRY", "CHIMNEY", "CLOVER", "COMPASS",
        "CORNER", "CRATER", "CURTAIN", "CUSHION", "DAHLIA", "DIAMOND", "DOLPHIN", "DRAWER",
        "FEATHER", "FIDDLE", "FLOWER", "GLACIER", "GRANITE", "HARVEST", "JASMINE", "JOURNAL",
        "KITCHEN", "LANTERN", "LAUNDRY", "LIZARD", "LOBSTER", "MAGNET", "MANGO", "MARKET",
        "MEADOW", "MELON", "MORTAR", "NECTAR", "NOODLE", "OCTOPUS", "ONION", "ORCHARD",
        "OSTRICH", "OTTER", "PADDLE", "PANTHER", "PARSLEY", "PASTURE", "PEACOCK", "PEANUT",
        "PENGUIN", "PICKLE", "PLASTER", "PLUM", "POPPY", "PRETZEL", "PUMPKIN", "QUARRY",
        "RACCOON", "RADISH", "RAFTER", "RAISIN", "RAVINE", "ROOSTER", "SAFFRON", "SATCHEL",
        "SEAWEED", "SHELTER", "SHRIMP", "SPINACH", "SPRUCE", "SQUID", "STATUE", "STRAW",
        "TANGERINE", "TEAPOT", "TERRACE", "THIMBLE", "THISTLE", "TOWEL", "TRACTOR", "TRUMPET",
        "TULIP", "TURNIP", "UMBRELLA", "VANILLA", "VIOLET", "WAFFLE", "WALRUS", "WHEAT"
    ]

    /// Words of a given length, for a puzzle that has to fit a grid.
    static func words(count: Int, minimumLength: Int, maximumLength: Int) -> [String] {
        let filtered = words.filter { $0.count >= minimumLength && $0.count <= maximumLength }
        let pool = filtered.isEmpty ? words : filtered
        return Array(Set(pool).shuffled().prefix(count))
    }

    /// Sentences to retype.
    ///
    /// Plain declarative statements about nothing in particular: a sentence you find
    /// interesting is a sentence you read instead of copying, and one that tells you off
    /// is a sentence you learn to resent. These are dull on purpose.
    static let phrases: [String] = [
        "The kettle in the corner has been boiling since half past four.",
        "Someone left a blue umbrella on the third step of the staircase.",
        "The map on the wall shows a river that no longer runs there.",
        "Two pigeons landed on the railing and neither of them stayed long.",
        "There are eleven wooden chairs stacked against the far wall.",
        "The clock above the door is four minutes faster than the one below it.",
        "A paper bag of walnuts sits on the windowsill in the afternoon sun.",
        "The last train to the coast leaves from the platform on the left.",
        "Rain collected in the gutter and ran down towards the garden gate.",
        "The library keeps its oldest atlases in a cabinet near the stairs.",
        "A grey cat crossed the yard and disappeared behind the shed.",
        "The recipe calls for three tomatoes, a lemon, and a pinch of salt.",
        "Every window on the second floor was opened at the same time.",
        "The ferry crosses twice an hour except on Sundays in the winter.",
        "A wooden bench faces the pond where the ducks gather each morning.",
        "The baker on the corner closes early on the first Monday of the month.",
        "Three brown envelopes were left leaning against the letterbox.",
        "The hallway light flickers whenever the front door is closed hard.",
        "A jar of pickled lemons has been at the back of the shelf since spring.",
        "The bus stops twice on the hill before it reaches the roundabout.",
        "Someone has chalked the day of the week on the board by the door.",
        "The greenhouse roof lost two panes in the storm last November.",
        "A wooden ladder leans against the wall beside the apple tree.",
        "The postman leaves the parcels under the porch when it rains.",
        "There is a chipped blue bowl on the counter holding loose change.",
        "The path to the beach narrows where the fence has fallen over.",
        "A radio plays quietly in the workshop across the courtyard.",
        "The oldest tree in the square was planted the year the school opened.",
        "Six bicycles are chained to the railing outside the bakery.",
        "The tide comes in fastest along the flat stretch past the rocks.",
        "A brass key hangs on a nail behind the kitchen door.",
        "The train timetable on the wall has been out of date for two years.",
        "Someone painted the shutters green and left the frames white.",
        "A stack of clay pots waits by the gate for the weekend.",
        "The stream behind the mill runs shallow until the autumn rain.",
        "Four crates of oranges were unloaded outside the shop this morning.",
        "The bell in the tower rings a minute later than the station clock.",
        "A long scratch runs down the side of the wooden table.",
        "The washing line stretches from the porch to the corner of the shed.",
        "Two ladders and a bucket were left at the foot of the stairs.",
        "The corner shop sells newspapers, milk, and very little else.",
        "A wasp got into the room through the gap above the window.",
        "The gravel path crunches differently after a week without rain.",
        "Someone stacked firewood against the north wall of the barn."
    ]

    /// A sentence of roughly the wanted length, and never the same one twice running.
    static func phrase(approximateWordCount: Int, excluding previous: String?) -> String {
        let ranked = phrases
            .filter { $0 != previous }
            .sorted {
                abs($0.split(separator: " ").count - approximateWordCount)
                    < abs($1.split(separator: " ").count - approximateWordCount)
            }
        // The closest third, chosen from at random: taking the single closest would hand
        // out the same sentence for a given length every time.
        let candidates = Array(ranked.prefix(max(ranked.count / 3, 3)))
        return candidates.randomElement() ?? phrases[0]
    }

    /// The glyphs "odd one out" is played with. Shapes rather than letters: a letter that
    /// differs is spotted by reading, and reading is fast.
    static let glyphs: [String] = [
        "circle.fill", "square.fill", "triangle.fill", "diamond.fill", "hexagon.fill",
        "seal.fill", "pentagon.fill", "capsule.fill", "rhombus.fill", "octagon.fill",
        "shield.fill", "heart.fill", "star.fill", "cloud.fill", "drop.fill", "leaf.fill"
    ]

    /// Shapes that genuinely take a second look, written down as pairs.
    ///
    /// The old version took a glyph and one of the next three in the list, on the stated
    /// assumption that the list was ordered by how alike its entries are. It is not
    /// ordered by anything, so the puzzle regularly asked which of eleven circles was the
    /// triangle -- which is not a puzzle, it is a formality with a delay on it. "Looks
    /// like" is not a property one shape has on its own, so it is stated per pair.
    static let confusablePairs: [(String, String)] = [
        ("circle.fill", "hexagon.fill"),
        ("hexagon.fill", "octagon.fill"),
        ("octagon.fill", "seal.fill"),
        ("seal.fill", "circle.fill"),
        ("circle.fill", "octagon.fill"),
        ("square.fill", "diamond.fill"),
        ("diamond.fill", "rhombus.fill"),
        ("rhombus.fill", "square.fill"),
        ("square.fill", "capsule.fill"),
        ("capsule.fill", "rectangle.fill"),
        ("triangle.fill", "pentagon.fill"),
        ("pentagon.fill", "hexagon.fill"),
        ("heart.fill", "drop.fill"),
        ("drop.fill", "leaf.fill"),
        ("cloud.fill", "shield.fill"),
        ("shield.fill", "seal.fill"),
        ("star.fill", "seal.fill"),
        ("star.fill", "sparkle")
    ]

    /// A shape and one that looks like it but is not, either way round.
    ///
    /// The order is flipped at random so the odd one is not always the rarer glyph of the
    /// two: a puzzle whose answer is "the unusual-looking one" is answered without
    /// counting.
    static func confusablePair() -> (common: String, odd: String) {
        let pair = confusablePairs.randomElement() ?? ("circle.fill", "hexagon.fill")
        return Bool.random() ? (common: pair.0, odd: pair.1) : (common: pair.1, odd: pair.0)
    }
}
