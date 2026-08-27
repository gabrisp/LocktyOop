import Foundation

struct AppwriteClient: APIClient {
    func isReachable() async -> Bool {
        false
    }
}
