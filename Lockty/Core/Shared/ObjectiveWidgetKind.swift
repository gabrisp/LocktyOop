import Foundation

/// The name the home-screen objectives widget goes by.
///
/// Shared because both sides need it and neither can see the other's code: the widget
/// declares itself with it, and the app asks WidgetKit to redraw it by it. A literal in
/// two places would work until one of them was renamed, and then the widget would simply
/// stop updating with nothing to show for it.
nonisolated enum ObjectiveWidgets {
    static let kind = "LocktyObjectives"
}

/// The name the home-screen scores widget goes by, shared for the same reason.
nonisolated enum DailyScoreWidgets {
    static let kind = "LocktyScores"
}
