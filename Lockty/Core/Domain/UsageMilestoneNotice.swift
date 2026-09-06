import Foundation

/// The "you have passed yesterday" notice.
///
/// The one claim about a day in progress that can be made at any hour without being
/// wrong. "Less screen time than yesterday" needs the day to be over; "already more time
/// in TikTok than the whole of yesterday" is true the moment the minute lands, at eight in
/// the morning or at eleven at night.
///
/// Written from the extension, because that is where the moment happens: iOS counts the
/// minutes and launches the monitor when the threshold is passed, with the app closed.
nonisolated enum UsageMilestoneNotice {
    static let activityPrefix = "lockty.milestone."
    static let eventName = "lockty.milestone.usage"

    /// How long yesterday has to have been before passing it is worth a notification.
    /// Twenty minutes: below that, passing it says more about yesterday than about today.
    static let minimumMinutes = 20

    /// How many apps are watched at once. Three notifications in a morning is a nag.
    static let maximumWatched = 2

    /// The app id this activity is watching.
    static func appID(from activityName: String) -> AppIdentity.ID? {
        guard activityName.hasPrefix(activityPrefix) else { return nil }
        let raw = String(activityName.dropFirst(activityPrefix.count))
        return raw.isEmpty ? nil : AppIdentity.ID(rawValue: raw)
    }

    static let title = "Past yesterday"

    /// The line. Names the app, because a notification that says "an app" is a
    /// notification about nothing -- which is why the name has to have been written down
    /// while an extension could still read it.
    static func message(appName: String, yesterday: String) -> String {
        "You have spent longer in \(appName) today than you did all of yesterday (\(yesterday))."
    }
}
