import Foundation
import ManagedSettings

nonisolated enum AppIconSource: Codable, Hashable {
    case appStoreArtworkURL(String)
    case screenTimeToken
    case systemImage(String)
    case placeholder

    var remoteURL: URL? {
        switch self {
        case .appStoreArtworkURL(let value):
            URL(string: value)
        case .screenTimeToken, .systemImage, .placeholder:
            nil
        }
    }
}

nonisolated struct AppIdentity: Codable, Hashable, Identifiable {
    nonisolated struct ID: RawRepresentable, Codable, Hashable, Identifiable, ExpressibleByStringLiteral {
        let rawValue: String

        var id: String { rawValue }

        init(rawValue: String) {
            self.rawValue = rawValue
        }

        init(stringLiteral value: StringLiteralType) {
            rawValue = value
        }
    }

    let id: ID
    var displayName: String
    var bundleIdentifier: String?
    var applicationToken: ManagedSettings.ApplicationToken?
    var iconSystemName: String?
    var iconSource: AppIconSource

    init(
        id: ID,
        displayName: String,
        bundleIdentifier: String? = nil,
        applicationToken: ManagedSettings.ApplicationToken? = nil,
        iconSystemName: String? = nil,
        iconSource: AppIconSource? = nil
    ) {
        self.id = id
        self.displayName = displayName
        self.bundleIdentifier = bundleIdentifier
        self.applicationToken = applicationToken
        self.iconSystemName = iconSystemName
        self.iconSource = iconSource ?? iconSystemName.map(AppIconSource.systemImage) ?? .placeholder
    }
}

extension AppIdentity.ID {
    nonisolated init(token: ManagedSettings.ApplicationToken) {
        let application = ManagedSettings.Application(token: token)
        if let bundleIdentifier = application.bundleIdentifier, !bundleIdentifier.isEmpty {
            self.init(rawValue: bundleIdentifier)
            return
        }

        if let displayName = application.localizedDisplayName, !displayName.isEmpty {
            self.init(rawValue: "display.\(displayName.lowercased())")
            return
        }

        self.init(rawValue: AppIdentity.ID.tokenIdentifier(for: token))
    }

    /// A stable, genuinely distinct id for a token with nothing else to go on.
    ///
    /// This used to be `String(describing: token)`, which prints the same text for every
    /// ApplicationToken -- so every app on the device collapsed into one identity. A
    /// routine blocking eleven apps resolved to a policy with one, every stored selection
    /// looked like a subset of every policy, and the merge then unioned every record it
    /// had: twenty scopes, twenty-four apps and three whole categories shielded at once.
    /// The encoded token is unique per app and stable across launches.
    nonisolated static func tokenIdentifier(for token: ManagedSettings.ApplicationToken) -> String {
        guard let data = try? JSONEncoder().encode(token) else {
            return "token.unknown"
        }
        return "token.\(data.base64EncodedString())"
    }
}

extension AppIdentity {
    nonisolated static func preferredDisplayName(
        localizedDisplayName: String?,
        bundleIdentifier: String?
    ) -> String {
        if let localizedDisplayName,
           !localizedDisplayName.isEmpty,
           !localizedDisplayName.contains(".") {
            return localizedDisplayName
        }

        if let bundleIdentifier,
           !bundleIdentifier.isEmpty {
            let candidate = bundleIdentifier
                .split(separator: ".")
                .last
                .map(String.init)?
                .replacingOccurrences(of: "-", with: " ")
                .replacingOccurrences(of: "_", with: " ")
                .trimmingCharacters(in: .whitespacesAndNewlines)

            if let candidate,
               !candidate.isEmpty {
                return candidate
                    .split(separator: " ")
                    .map { part in
                        let value = String(part)
                        guard let first = value.first else { return value }
                        return first.uppercased() + value.dropFirst()
                    }
                    .joined(separator: " ")
            }
        }

        return "App"
    }

    nonisolated init(token: ManagedSettings.ApplicationToken) {
        let application = ManagedSettings.Application(token: token)
        let displayName = AppIdentity.preferredDisplayName(
            localizedDisplayName: application.localizedDisplayName,
            bundleIdentifier: application.bundleIdentifier
        )
        let bundleIdentifier = application.bundleIdentifier
        let iconSystemName = bundleIdentifier == nil ? "app.fill" : nil
        self.init(
            id: AppIdentity.ID(token: token),
            displayName: displayName,
            bundleIdentifier: bundleIdentifier,
            applicationToken: token,
            iconSystemName: iconSystemName,
            iconSource: .screenTimeToken
        )
    }
}

extension String {
    /// A UUID derived from this string, so an unlock request for an app that no routine
    /// owns still has a stable id to key its notification and its pending event on.
    nonisolated var stableUUID: UUID {
        var bytes = Array(Data(utf8).prefix(16))
        while bytes.count < 16 { bytes.append(0) }
        return UUID(uuid: (
            bytes[0], bytes[1], bytes[2], bytes[3],
            bytes[4], bytes[5], bytes[6], bytes[7],
            bytes[8], bytes[9], bytes[10], bytes[11],
            bytes[12], bytes[13], bytes[14], bytes[15]
        ))
    }
}
