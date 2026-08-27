import Foundation
import ManagedSettings

enum ApplicationTokenCoding {
    static func encode(_ token: ManagedSettings.ApplicationToken?) -> Data? {
        guard let token else { return nil }
        return try? JSONEncoder().encode(token)
    }

    static func decode(_ data: Data?) -> ManagedSettings.ApplicationToken? {
        guard let data else { return nil }
        return try? JSONDecoder().decode(ManagedSettings.ApplicationToken.self, from: data)
    }
}
