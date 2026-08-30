import Foundation

struct FocusCreationChoiceRoute: Hashable, Identifiable {
    let draftID: UUID
    let routineDraftID: UUID
    let frictionDraftID: UUID

    init(
        draftID: UUID = UUID(),
        routineDraftID: UUID = UUID(),
        frictionDraftID: UUID = UUID()
    ) {
        self.draftID = draftID
        self.routineDraftID = routineDraftID
        self.frictionDraftID = frictionDraftID
    }

    var id: UUID { draftID }
}

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

struct PauseFlowEditorRoute: Hashable, Identifiable {
    let flowID: UUID?
    let draftID: UUID

    init(flowID: UUID?, draftID: UUID = UUID()) {
        self.flowID = flowID
        self.draftID = draftID
    }

    var id: UUID { draftID }
}

struct FrictionEditorRoute: Hashable, Identifiable {
    let frictionID: UUID?
    let draftID: UUID

    init(frictionID: UUID?, draftID: UUID = UUID()) {
        self.frictionID = frictionID
        self.draftID = draftID
    }

    var id: UUID { draftID }
}

struct AppGroupEditorRoute: Hashable, Identifiable {
    let appGroupID: UUID?
    let draftID: UUID

    init(appGroupID: UUID?, draftID: UUID = UUID()) {
        self.appGroupID = appGroupID
        self.draftID = draftID
    }

    var id: UUID { draftID }
}
