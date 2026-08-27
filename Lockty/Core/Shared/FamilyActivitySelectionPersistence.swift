import FamilyControls
import Foundation

enum FamilyActivitySelectionPersistenceError: LocalizedError {
    case decodeFailed

    var errorDescription: String? {
        switch self {
        case .decodeFailed:
            "Lockty could not decode the saved Screen Time selection."
        }
    }
}

extension FamilyActivitySelection {
    nonisolated func archivedData() throws -> Data? {
        let hasContent = !applicationTokens.isEmpty || !categoryTokens.isEmpty || !webDomainTokens.isEmpty
        guard hasContent else { return nil }

        if let data = try? PropertyListEncoder().encode(self), !data.isEmpty {
            return data
        }

        if let data = try? JSONEncoder().encode(self), !data.isEmpty {
            return data
        }

        return nil
    }

    nonisolated static func unarchive(from data: Data?) throws -> FamilyActivitySelection? {
        guard let data, !data.isEmpty else { return nil }

        if let selection = try? PropertyListDecoder().decode(FamilyActivitySelection.self, from: data) {
            return selection
        }

        if let selection = try? JSONDecoder().decode(FamilyActivitySelection.self, from: data) {
            return selection
        }

        throw FamilyActivitySelectionPersistenceError.decodeFailed
    }
}
