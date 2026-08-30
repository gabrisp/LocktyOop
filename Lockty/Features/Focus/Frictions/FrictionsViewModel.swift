import Foundation
import Combine
import SwiftUI

@MainActor
final class FrictionsViewModel: ObservableObject {
    private let repository: FrictionRepository
    @Published private(set) var frictions: [Friction] = []
    @Published var errorMessage: String?

    init(repository: FrictionRepository) {
        self.repository = repository
    }

    func load() async {
        let loaded = await repository.frictions()
        withAnimation(.smooth(duration: 0.28)) {
            frictions = loaded
        }
    }

    func delete(id: UUID) async {
        do {
            try await repository.delete(id: id)
            frictions.removeAll { $0.id == id }
        } catch {
            errorMessage = error.localizedDescription
        }
    }
}
