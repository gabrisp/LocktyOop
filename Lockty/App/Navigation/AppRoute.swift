import Foundation

enum AppRoute: Hashable {
    case routinesList
    case frictionsList
    case appsList
    case distractingGroup
    case distractingApps
    case distractingIntervention
    case distractingFriction
    case appGroupEditor(AppGroupEditorRoute)
    case appGroupSelection(AppGroupEditorRoute)
}
