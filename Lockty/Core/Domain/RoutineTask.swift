import Foundation

nonisolated struct RoutineTask: Codable, Hashable, Identifiable {
    let id: UUID
    var title: String
    var icon: String?
    var order: Int
    var isOptional: Bool

    init(
        id: UUID = UUID(),
        title: String,
        icon: String? = nil,
        order: Int,
        isOptional: Bool = false
    ) {
        self.id = id
        self.title = title
        self.icon = icon
        self.order = order
        self.isOptional = isOptional
    }
}

nonisolated struct RoutineTaskCompletion: Codable, Hashable, Identifiable {
    let id: UUID
    var taskID: UUID
    var titleSnapshot: String
    var orderSnapshot: Int
    var completedAt: Date?

    init(
        id: UUID = UUID(),
        taskID: UUID,
        titleSnapshot: String,
        orderSnapshot: Int,
        completedAt: Date? = nil
    ) {
        self.id = id
        self.taskID = taskID
        self.titleSnapshot = titleSnapshot
        self.orderSnapshot = orderSnapshot
        self.completedAt = completedAt
    }
}
