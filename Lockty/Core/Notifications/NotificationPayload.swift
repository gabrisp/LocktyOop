import Foundation

struct NotificationPayload: Codable, Hashable, Identifiable {
    let id: UUID
    var type: NotificationType
    var routineID: UUID?
    var pauseContext: PauseContext?
    var createdAt: Date
    var idempotencyKey: String

    init(
        id: UUID = UUID(),
        type: NotificationType,
        routineID: UUID? = nil,
        pauseContext: PauseContext? = nil,
        createdAt: Date = Date(),
        idempotencyKey: String
    ) {
        self.id = id
        self.type = type
        self.routineID = routineID
        self.pauseContext = pauseContext
        self.createdAt = createdAt
        self.idempotencyKey = idempotencyKey
    }
}
