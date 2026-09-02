import Foundation

/// The blocking that is not a list of apps.
///
/// Everything else a routine shields is something you picked -- an app, a category, a
/// site. These three are switches on the device itself: the web filter, the App Store's
/// purchase flow, and installing apps at all. They are worth having precisely because
/// they close the doors a blocked app leaves open. Shielding Instagram does nothing if
/// you can install it again from the App Store thirty seconds later.
nonisolated struct ContentRestrictions: Codable, Hashable, Sendable {
    /// Apple's automatic adult-content filter, applied to web browsing.
    var blocksAdultWebContent: Bool
    /// Purchases and in-app purchases through the App Store.
    var blocksITunesPurchases: Bool
    /// Installing apps. Removal is left alone: locking someone out of deleting an app is
    /// a different thing from stopping them adding one, and only the second is blocking.
    var blocksAppInstallation: Bool

    init(
        blocksAdultWebContent: Bool = false,
        blocksITunesPurchases: Bool = false,
        blocksAppInstallation: Bool = false
    ) {
        self.blocksAdultWebContent = blocksAdultWebContent
        self.blocksITunesPurchases = blocksITunesPurchases
        self.blocksAppInstallation = blocksAppInstallation
    }

    static let none = ContentRestrictions()

    /// How many of the three are on, for the places that count what a routine shuts.
    var enabledCount: Int {
        [blocksAdultWebContent, blocksITunesPurchases, blocksAppInstallation]
            .filter { $0 }
            .count
    }

    var isEmpty: Bool {
        !blocksAdultWebContent && !blocksITunesPurchases && !blocksAppInstallation
    }

    /// The strictest of the two, switch by switch.
    ///
    /// The same shape as the rest of the shield: several routines can be running, and
    /// what the device does is what any one of them asked for. A routine ending simply
    /// drops out of the union.
    func union(_ other: ContentRestrictions) -> ContentRestrictions {
        ContentRestrictions(
            blocksAdultWebContent: blocksAdultWebContent || other.blocksAdultWebContent,
            blocksITunesPurchases: blocksITunesPurchases || other.blocksITunesPurchases,
            blocksAppInstallation: blocksAppInstallation || other.blocksAppInstallation
        )
    }

    // Every field optional on the way in, so a routine or a shield policy written before
    // any of this existed decodes as "none" instead of throwing and taking the shield
    // down with it.
    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        blocksAdultWebContent = try container.decodeIfPresent(Bool.self, forKey: .blocksAdultWebContent) ?? false
        blocksITunesPurchases = try container.decodeIfPresent(Bool.self, forKey: .blocksITunesPurchases) ?? false
        blocksAppInstallation = try container.decodeIfPresent(Bool.self, forKey: .blocksAppInstallation) ?? false
    }
}
