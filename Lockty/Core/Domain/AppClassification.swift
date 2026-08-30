import Foundation

enum AppClassification: String, CaseIterable, Codable, Hashable, Identifiable {
    case productive
    case neutral
    case unproductive

    var id: String { rawValue }

    var title: String {
        switch self {
        case .productive: "Productive"
        case .neutral: "Neutral"
        case .unproductive: "Unproductive"
        }
    }

    var scoringWeight: Double {
        switch self {
        case .productive: 1.0
        case .neutral: 0.5
        case .unproductive: 0.0
        }
    }
}

enum AppClassificationHeuristics {
    private static let productiveKeywords: [String] = [
        "calendar", "gmail", "mail", "docs", "drive", "excel", "figma",
        "jira", "linear", "meet", "notion", "outlook", "safari",
        "settings", "sheet", "slack", "teams", "word", "xcode", "zoom"
    ]

    private static let unproductiveKeywords: [String] = [
        "bereal", "brawl", "clashroyale", "clash", "discord", "facebook",
        "instagram", "musically", "netflix", "pokemon", "reddit", "snapchat",
        "supercell", "telegram", "threads", "tiktok", "tinder", "twitch",
        "twitter", "x", "youtube"
    ]

    static func classification(
        appID: AppIdentity.ID,
        displayName: String? = nil,
        bundleIdentifier: String? = nil
    ) -> AppClassification? {
        let rawCandidates = [
            appID.rawValue,
            displayName ?? "",
            bundleIdentifier ?? ""
        ]

        let normalized = rawCandidates
            .joined(separator: " ")
            .folding(options: [.diacriticInsensitive, .caseInsensitive], locale: .current)
            .lowercased()

        if matchesAnyKeyword(in: normalized, keywords: unproductiveKeywords) {
            return .unproductive
        }

        if matchesAnyKeyword(in: normalized, keywords: productiveKeywords) {
            return .productive
        }

        return nil
    }

    private static func matchesAnyKeyword(in normalizedValue: String, keywords: [String]) -> Bool {
        keywords.contains { keyword in
            normalizedValue.contains(keyword)
        }
    }
}
