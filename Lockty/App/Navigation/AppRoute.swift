import Foundation

enum AppRoute: Hashable {
    case rulesList
    case routinesList
    case frictionsList
    case appsList
    case distractingGroup
    case alwaysAllowedGroup
    case distractingApps
    case distractingIntervention
    case distractingFriction
    case appGroupEditor(AppGroupEditorRoute)
    case appGroupSelection(AppGroupEditorRoute)
}
