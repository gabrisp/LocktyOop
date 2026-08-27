import Foundation

nonisolated struct PendingSystemEvent: Codable, Hashable, Identifiable {
    let id: UUID
    var source: SystemEventSource
    var payload: SystemEventPayload
    var createdAt: Date
    var expiresAt: Date?
    var idempotencyKey: String

    init(
        id: UUID = UUID(),
        source: SystemEventSource,
        payload: SystemEventPayload,
        createdAt: Date = Date(),
        expiresAt: Date? = nil,
        idempotencyKey: String
    ) {
        self.id = id
        self.source = source
        self.payload = payload
        self.createdAt = createdAt
        self.expiresAt = expiresAt
        self.idempotencyKey = idempotencyKey
    }

    var isExpired: Bool {
        guard let expiresAt else { return false }
        return Date() >= expiresAt
    }
}

nonisolated enum SystemEventSource: String, Codable, Hashable {
    case shieldAction
    case notification
    case deepLink
    case nfc
    case alarm
    case location
    case deviceActivity
}

nonisolated enum SystemEventPayload: Codable, Hashable {
    case pauseRequested(PauseContext)
    case routineStartRequested(UUID)
    case settingsRequested
}
