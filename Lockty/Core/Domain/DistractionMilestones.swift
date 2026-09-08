import Foundation

/// The notices that arrive as a day in distracting apps piles up.
///
/// One per threshold rather than one a day. Fifteen minutes and ninety minutes are not
/// the same fact about an afternoon, and a single notification set at whichever number
/// somebody chose in a menu can only ever say one of them.
///
/// Each is a usage threshold registered with DeviceActivity, so iOS counts the minutes
/// and launches the monitor extension the moment one is crossed -- with Lockty closed,
/// with nothing polling, with nothing to be woken up.
///
/// The lines are the whole point of the feature. They do not scold and they do not
/// congratulate: they say the figure, and then they leave a door open. Somebody reading
/// this has already decided these apps are a problem -- being told off for it is the one
/// thing that would make them turn the notifications off.
nonisolated enum DistractionMilestones {
    /// One way of saying a milestone. Several per milestone, so the same figure does not
    /// arrive in the same words every day.
    struct Line: Hashable {
        let title: String
        let body: String
    }

    /// What a notice can mention beyond the figure it fired on.
    ///
    /// Read at the moment of delivery from the report snapshots, because that is the only
    /// place these numbers exist -- and because a notice that says "34 min, most of it
    /// Instagram" is answering a question the bare figure only raises.
    struct Context: Hashable {
        var topAppName: String?
        var topAppMinutes: Int?
        var topAppPickups: Int?
        var yesterdayMinutes: Int?
        var todayTotalMinutes: Int?

        static let none = Context()
    }

    struct Milestone: Hashable, Identifiable {
        let minutes: Int
        /// Every way this one can be put. Never empty.
        let lines: [Line]

        var id: Int { minutes }
        /// The event name this milestone is registered under.
        var eventName: String { "\(DistractionMilestones.eventPrefix)\(minutes)" }

        var title: String { lines[0].title }
        var body: String { lines[0].body }
    }

    static let eventPrefix = "lockty.autofocus.usage."

    /// The minutes a milestone fired at, read back off the event name.
    static func minutes(from eventName: String) -> Int? {
        guard eventName.hasPrefix(eventPrefix) else { return nil }
        return Int(eventName.dropFirst(eventPrefix.count))
    }

    static func milestone(forEvent eventName: String) -> Milestone? {
        guard let minutes = minutes(from: eventName) else { return nil }
        return all.first { $0.minutes == minutes }
    }

    /// Every step there is. Which of them are actually registered depends on the level.
    static let all: [Milestone] = [
        Milestone(minutes: 5, lines: [
            Line(title: "Five minutes in", body: "Over 5 min in distracting apps today. This is still easy to reset."),
            Line(title: "Five minutes", body: "That is 5 min gone. Nothing has happened since you opened it."),
            Line(title: "Still here", body: "5 min in. Was this the plan?")
        ]),
        Milestone(minutes: 10, lines: [
            Line(title: "Ten minutes in", body: "Over 10 min in distracting apps today. Worth checking you meant to stay."),
            Line(title: "Ten minutes", body: "10 min. Long enough to have finished the thing you opened this instead of."),
            Line(title: "Ten and counting", body: "10 min in distracting apps. The next one is a choice.")
        ]),
        Milestone(minutes: 15, lines: [
            Line(title: "It is adding up", body: "Over 15 min in distracting apps today. A small reset still counts."),
            Line(title: "A quarter of an hour", body: "15 min. That is a walk, a call, or a chapter."),
            Line(title: "Fifteen minutes", body: "15 min today. Still an easy number to stop at.")
        ]),
        Milestone(minutes: 30, lines: [
            Line(title: "Half an hour in", body: "Over 30 min today. A good moment to close the tab."),
            Line(title: "Thirty minutes", body: "30 min in apps you called distracting. Is there something you meant to do first?"),
            Line(title: "Half an hour", body: "30 min. The feed will still be there later; it is built that way.")
        ]),
        Milestone(minutes: 45, lines: [
            Line(title: "A heavy screen day?", body: "Over 45 min in distracting apps. Make the next minute an offline one."),
            Line(title: "Forty-five minutes", body: "45 min today. That is most of a lunch break."),
            Line(title: "Three quarters of an hour", body: "45 min in. Worth asking what you came here for.")
        ]),
        Milestone(minutes: 60, lines: [
            Line(title: "An hour gone", body: "An hour today in apps you called distracting. Nothing new has happened since you started."),
            Line(title: "One hour", body: "60 min. Tomorrow this is the number you will remember."),
            Line(title: "An hour in", body: "An hour of your day, spent here. The rest of it is still yours.")
        ])
    ]

    /// The line to send, chosen from everything this milestone could say.
    ///
    /// Stable within a day and different between days: the same threshold re-delivered
    /// must not arrive worded two ways, and the same threshold tomorrow must not arrive
    /// worded the same. Seeded off the day key with a hash written out by hand, because
    /// Swift's own is seeded per process and would reword the notice on every launch.
    ///
    /// Weighted towards the lines that carry a figure -- which app, how it compares with
    /// yesterday, what share of the day it is. Those are the ones worth reading; the plain
    /// ones are what is left when Screen Time has not reported yet.
    static func line(
        for milestone: Milestone,
        context: Context = .none,
        on date: Date = Date()
    ) -> Line {
        let informed = informedLines(minutes: milestone.minutes, context: context)
        let seed = seed(dayKey: RuleEnforcementState.dayKey(for: date), minutes: milestone.minutes)

        guard !informed.isEmpty, seed % 3 != 0 else {
            return milestone.lines[seed % milestone.lines.count]
        }
        return informed[seed % informed.count]
    }

    /// The lines that need something Screen Time has actually reported.
    private static func informedLines(minutes: Int, context: Context) -> [Line] {
        var lines: [Line] = []
        let spent = durationText(minutes)

        if let app = context.topAppName, let appMinutes = context.topAppMinutes, appMinutes > 0 {
            lines.append(
                Line(
                    title: "\(spent) in distracting apps",
                    body: "Most of it is \(app) — \(durationText(appMinutes)). The rest of the day is still open."
                )
            )
            if let pickups = context.topAppPickups, pickups >= 3 {
                lines.append(
                    Line(
                        title: "\(app), \(pickups) times",
                        body: "You have opened it \(pickups) times today, for \(durationText(appMinutes)). Each one felt like a second."
                    )
                )
            }
        }

        if let yesterday = context.yesterdayMinutes, yesterday > 0 {
            if minutes >= yesterday {
                lines.append(
                    Line(
                        title: "Past yesterday already",
                        body: "\(spent) today, and yesterday finished on \(durationText(yesterday))."
                    )
                )
            } else {
                lines.append(
                    Line(
                        title: "\(spent) so far",
                        body: "Yesterday finished on \(durationText(yesterday)). Today is not written yet."
                    )
                )
            }
        }

        if let total = context.todayTotalMinutes, total >= minutes, total > 0 {
            let share = Int((Double(minutes) / Double(total) * 100).rounded())
            if share >= 10 {
                lines.append(
                    Line(
                        title: "\(share)% of your screen today",
                        body: "\(spent) of the \(durationText(total)) you have spent on this phone."
                    )
                )
            }
        }

        return lines
    }

    /// "45 min", "1 h", "1 h 20 m" -- the way the rest of the app writes a length.
    private static func durationText(_ minutes: Int) -> String {
        guard minutes >= 60 else { return "\(minutes) min" }
        let hours = minutes / 60
        let remainder = minutes % 60
        return remainder == 0 ? "\(hours) h" : "\(hours) h \(remainder) m"
    }

    /// FNV-1a over the day and the threshold. Written out rather than using `hashValue`,
    /// which is seeded per process and would pick a different line on every launch.
    private static func seed(dayKey: String, minutes: Int) -> Int {
        var hash: UInt64 = 0xcbf2_9ce4_8422_2325
        for byte in Array("\(dayKey)-\(minutes)".utf8) {
            hash ^= UInt64(byte)
            hash = hash &* 0x100_0000_01b3
        }
        return Int(hash % UInt64(Int.max))
    }

    /// Which milestones a level is worth being interrupted by.
    ///
    /// The level was a single threshold and a cooldown; it is now how often you want to
    /// hear from the app at all. Low speaks twice in a heavy day, high speaks at every
    /// step -- and nobody is told anything twice, because a threshold fires once per day
    /// by construction.
    static func milestones(for level: AutoFocusInterventionLevel) -> [Milestone] {
        switch level {
        case .low: all.filter { $0.minutes >= 30 }
        case .medium: all.filter { [10, 15, 30, 60].contains($0.minutes) }
        case .high: all
        }
    }
}
