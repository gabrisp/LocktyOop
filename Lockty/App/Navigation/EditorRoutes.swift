import Foundation

struct RoutineEditorRoute: Hashable, Identifiable {
    let routineID: UUID?
    let draftID: UUID

    init(routineID: UUID?, draftID: UUID = UUID()) {
        self.routineID = routineID
        self.draftID = draftID
    }

    var id: UUID { draftID }
}

struct PauseEditorRoute: Hashable, Identifiable {
    let pauseID: UUID?
    let draftID: UUID

    init(pauseID: UUID?, draftID: UUID = UUID()) {
        self.pauseID = pauseID
        self.draftID = draftID
    }

    var id: UUID { draftID }
}
