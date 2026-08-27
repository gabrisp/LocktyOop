import Foundation

protocol APIClient {
    func isReachable() async -> Bool
}
