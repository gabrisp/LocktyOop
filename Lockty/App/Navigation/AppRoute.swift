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
    /// One of the three daily scores, explained.
    case scoreDetail(day: Date, kind: PrimaryMetricKind)
    /// What you meant to do, and how far along each one is.
    ///
    /// Carries one to single out, for the quick cards on Today: tapping a name there is
    /// asking about that objective, so the page opens with it already picked rather than
    /// leaving you to find it again in the row.
    case objectives(focused: UUID?)
    /// What the rules did, and how each of them has been going.
    case ruleStats
}
