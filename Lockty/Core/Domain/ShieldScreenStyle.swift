import Foundation

/// Which packs the block screen draws from, and the line the person wrote for themselves.
///
/// A set rather than one choice: several packs on at once is what keeps the shield from
/// becoming a thing you have read. When more than one is enabled a pack is picked at
/// random each time the shield is drawn, and then a line from inside it.
nonisolated struct ShieldScreenPreferences: Codable, Hashable, Sendable {
    var enabledPackIDs: Set<String>
    /// The line the "Your reason" pack shows. Empty means that pack has nothing to say
    /// and is skipped, since a blank reason is not a reason.
    var intention: String

    init(
        enabledPackIDs: Set<String> = [ShieldScreenCatalog.defaultPackID],
        intention: String = ""
    ) {
        self.enabledPackIDs = enabledPackIDs
        self.intention = intention
    }

    static let `default` = ShieldScreenPreferences()

    // Tolerant on the way in, and on two counts. A file written before packs existed
    // carries a single `style` string, which maps onto the pack of the same name; one
    // written before any of this carries neither, and falls back to the default rather
    // than leaving the shield with nothing to say.
    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        intention = try container.decodeIfPresent(String.self, forKey: .intention) ?? ""

        if let ids = try container.decodeIfPresent(Set<String>.self, forKey: .enabledPackIDs), !ids.isEmpty {
            enabledPackIDs = ids
        } else if let legacyStyle = try container.decodeIfPresent(String.self, forKey: .style) {
            enabledPackIDs = [Self.packID(forLegacyStyle: legacyStyle)]
        } else {
            enabledPackIDs = [ShieldScreenCatalog.defaultPackID]
        }
    }

    // Written by hand as well, so the legacy `style` key is not carried forward: it is
    // read once on the way in and never written again.
    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(enabledPackIDs, forKey: .enabledPackIDs)
        try container.encode(intention, forKey: .intention)
    }

    private enum CodingKeys: String, CodingKey {
        case enabledPackIDs
        case intention
        case style
    }

    private static func packID(forLegacyStyle style: String) -> String {
        switch style {
        case "cost": "cost"
        case "intention": "intention"
        case "quiet": "quiet"
        default: ShieldScreenCatalog.defaultPackID
        }
    }

    /// Enabling nothing is not an option the list offers, so the default stands in.
    var resolvedPackIDs: Set<String> {
        enabledPackIDs.isEmpty ? [ShieldScreenCatalog.defaultPackID] : enabledPackIDs
    }

    var isSilent: Bool { resolvedPackIDs.contains("quiet") }

    func isEnabled(_ pack: ShieldScreenPack) -> Bool {
        resolvedPackIDs.contains(pack.id)
    }

    /// Turning one on or off, with the two rules the list has.
    ///
    /// Quiet is exclusive -- "say nothing" and "say this" cannot both be true -- and the
    /// last one cannot be turned off, because a shield with no pack has no message and
    /// the screen would silently become Quiet without saying so.
    mutating func toggle(_ pack: ShieldScreenPack) {
        var ids = resolvedPackIDs

        if pack.source == .silence {
            enabledPackIDs = ids.contains(pack.id) ? [ShieldScreenCatalog.defaultPackID] : [pack.id]
            return
        }

        ids.remove("quiet")

        if ids.contains(pack.id) {
            ids.remove(pack.id)
            if ids.isEmpty { ids = [ShieldScreenCatalog.defaultPackID] }
        } else {
            ids.insert(pack.id)
        }

        enabledPackIDs = ids
    }

    /// The line to show, given what the day can supply.
    ///
    /// `cost` and `intention` are asked for what they have and dropped when they have
    /// nothing: a pack that would print "0 min here today" or an empty quotation is worse
    /// than one that quietly stands aside and lets another speak.
    func message(cost: String?, randomSource: () -> Double = { Double.random(in: 0..<1) }) -> String? {
        guard !isSilent else { return nil }

        let trimmedIntention = intention.trimmingCharacters(in: .whitespacesAndNewlines)
        let candidates: [String] = ShieldScreenCatalog.packs
            .filter { resolvedPackIDs.contains($0.id) }
            .compactMap { pack in
                switch pack.source {
                case .silence:
                    return nil
                case .cost:
                    return cost.map { "\($0) here today." }
                case .intention:
                    return trimmedIntention.isEmpty ? nil : "\u{201C}\(trimmedIntention)\u{201D}"
                case .messages:
                    guard !pack.messages.isEmpty else { return nil }
                    let index = min(Int(randomSource() * Double(pack.messages.count)), pack.messages.count - 1)
                    return pack.messages[index]
                }
            }

        guard !candidates.isEmpty else {
            return ShieldScreenCatalog.pack(id: ShieldScreenCatalog.defaultPackID)?.messages.first
        }

        let index = min(Int(randomSource() * Double(candidates.count)), candidates.count - 1)
        return candidates[index]
    }

    /// What the Settings row says without opening the screen.
    var summary: String {
        if isSilent { return "Quiet" }
        let count = resolvedPackIDs.count
        guard count > 1 else {
            return ShieldScreenCatalog.pack(id: resolvedPackIDs.first ?? "")?.title ?? "Default"
        }
        return "\(count) packs"
    }
}
