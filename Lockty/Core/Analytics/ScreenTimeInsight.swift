import Foundation

/// One sentence about the day, with the figure in it worth reading twice.
///
/// Written from the day's own numbers rather than generated: an on-device model could
/// phrase these more warmly, but it cannot know anything these do not already say, and a
/// sentence that is occasionally wrong about your own day is worse than one that is
/// plainly phrased and always right. The shape is deliberately model-ready -- a glyph, a
/// sentence, and the spans inside it to emphasise -- so swapping the writer changes only
/// where the strings come from.
struct ScreenTimeInsight: Identifiable, Hashable {
    let id: String
    var systemImage: String
    /// The sentence, with `%@` already filled in.
    var text: String
    /// The substrings drawn in the accent colour. Matched by value, so the same figure
    /// appearing twice is highlighted twice, which is correct.
    var emphasis: [String]
    var tone: Tone

    enum Tone: Hashable {
        case good
        case neutral
        case warning
    }
}

/// Reads a day and says what stands out about it.
///
/// Every insight is conditional on having the data behind it. A day with no pickup
/// counts produces no insight about pickups rather than an insight saying zero -- Screen
/// Time delivers these late and unevenly, and a confident "you opened nothing today" is
/// worse than saying nothing.
struct ScreenTimeInsightBuilder {
    func insights(
        apps: [AppUsageState],
        hourly: HourlyActivityState,
        totalUsage: TimeInterval
    ) -> [ScreenTimeInsight] {
        var insights: [ScreenTimeInsight] = []

        if let heaviest = apps.max(by: { $0.duration < $1.duration }), heaviest.duration >= 60 {
            let duration = LocktyDurationFormatter.abbreviated(heaviest.duration)
            if heaviest.opens >= 5 {
                let opens = "\(heaviest.opens) times"
                insights.append(
                    ScreenTimeInsight(
                        id: "heaviest-app",
                        systemImage: "hand.tap",
                        text: "You opened \(heaviest.app.displayName) \(opens) and spent \(duration) there.",
                        emphasis: [opens, duration],
                        tone: heaviest.classification == .unproductive ? .warning : .neutral
                    )
                )
            } else {
                insights.append(
                    ScreenTimeInsight(
                        id: "heaviest-app",
                        systemImage: "hourglass",
                        text: "\(heaviest.app.displayName) took \(duration), more than anything else today.",
                        emphasis: [duration],
                        tone: heaviest.classification == .unproductive ? .warning : .neutral
                    )
                )
            }
        }

        // The busiest hour, which is the one thing an average cannot tell you: two people
        // with four hours each had entirely different days if one of them spent ninety
        // minutes of it between nine and ten.
        if let peak = hourly.hours.max(by: { $0.usage < $1.usage }), peak.usage >= 15 * 60 {
            let window = String(format: "%d:00 - %d:00", peak.hour, (peak.hour + 1) % 24)
            let duration = LocktyDurationFormatter.abbreviated(peak.usage)
            insights.append(
                ScreenTimeInsight(
                    id: "peak-hour",
                    systemImage: "chart.bar.fill",
                    text: "Your heaviest hour was \(window), with \(duration) on screen.",
                    emphasis: [window, duration],
                    tone: .neutral
                )
            )
        }

        // The first thing you reach for, which people are almost always surprised by.
        if let firstHour = hourly.hours.first(where: { $0.usage >= 5 * 60 }) {
            let window = String(format: "%d:00", firstHour.hour)
            insights.append(
                ScreenTimeInsight(
                    id: "first-hour",
                    systemImage: "sunrise",
                    text: "Your day started on screen around \(window).",
                    emphasis: [window],
                    tone: firstHour.hour < 8 ? .warning : .neutral
                )
            )
        }

        if hourly.totalUnlocks >= 10 {
            let unlocks = "\(hourly.totalUnlocks)"
            let average = totalUsage > 0 ? totalUsage / Double(hourly.totalUnlocks) : 0
            let session = LocktyDurationFormatter.abbreviated(average)
            insights.append(
                ScreenTimeInsight(
                    id: "pickups",
                    systemImage: "iphone.gen3",
                    text: "You picked up your phone \(unlocks) times, about \(session) each.",
                    emphasis: [unlocks, session],
                    tone: hourly.totalUnlocks >= 80 ? .warning : .neutral
                )
            )
        }

        if hourly.totalNotifications >= 20 {
            let count = "\(hourly.totalNotifications)"
            insights.append(
                ScreenTimeInsight(
                    id: "notifications",
                    systemImage: "bell.badge",
                    text: "\(count) notifications arrived today.",
                    emphasis: [count],
                    tone: hourly.totalNotifications >= 100 ? .warning : .neutral
                )
            )
        }

        // The good news, said only when it is true.
        if let reduction = hourly.reductionVersusBaseline, reduction >= 10 * 60 {
            let saved = LocktyDurationFormatter.abbreviated(reduction)
            insights.append(
                ScreenTimeInsight(
                    id: "reduction",
                    systemImage: "arrow.down.right",
                    text: "That is \(saved) less than your usual day.",
                    emphasis: [saved],
                    tone: .good
                )
            )
        }

        let productive = apps.filter { $0.classification == .productive }.reduce(0) { $0 + $1.duration }
        if productive >= 20 * 60, totalUsage > 0 {
            let share = "\(Int((productive / totalUsage * 100).rounded()))%"
            insights.append(
                ScreenTimeInsight(
                    id: "productive-share",
                    systemImage: "leaf",
                    text: "\(share) of your screen time went to things you called productive.",
                    emphasis: [share],
                    tone: .good
                )
            )
        }

        return insights
    }
}
