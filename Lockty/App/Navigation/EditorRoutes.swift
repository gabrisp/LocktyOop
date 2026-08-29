import Foundation

struct RoutineEditorRoute: Hashable, Identifiable {
    let routineID: UUID?
    let draftID: UUID
    /// Opening an existing routine starts read-only; the pencil switches the same
    /// view into editing. Creating one starts editable, since there's nothing to read.
    let startsEditing: Bool

    init(routineID: UUID?, draftID: UUID = UUID(), startsEditing: Bool? = nil) {
        self.routineID = routineID
        self.draftID = draftID
        self.startsEditing = startsEditing ?? (routineID == nil)
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
