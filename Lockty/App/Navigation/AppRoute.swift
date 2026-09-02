import Foundation

enum AppRoute: Hashable {
    case rulesList
    case routinesList
    case frictionsList
    case appsList
    case distractingGroup
    case alwaysAllowedGroup
    case settings
    case distractingApps
    case distractingIntervention
    case distractingFriction
    /// The day's screen time in full: the badge again, the values behind it, and what
    /// they add up to. Pushed rather than presented -- it is a place you go and come
    /// back from, not something asking to be answered.
    case screenTimeInsights(day: Date)
    /// What the shield says when it stops you.
    case blockScreens
    /// Where the time went, by app, over a day, a week or a month.
    case usageBreakdown(day: Date)
}
