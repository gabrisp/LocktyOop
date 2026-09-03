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
        "A wooden bench faces the pond where the ducks gather each morning."
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

    /// A glyph and one that looks like it but is not. Chosen as neighbours in the list,
    /// which is ordered so that adjacent entries are the hardest to tell apart.
    static func confusablePair() -> (common: String, odd: String) {
        let index = Int.random(in: 0..<glyphs.count)
        let other = (index + Int.random(in: 1...3)) % glyphs.count
        return (glyphs[index], glyphs[other])
    }
}
