import Foundation
@testable import Lockty

@MainActor
enum CoreDataTestSupport {
    static func makeInMemoryController() -> PersistenceController {
        PersistenceController(inMemory: true)
    }
}
