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

        self.init(rawValue: "token.\(String(describing: token))")
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
