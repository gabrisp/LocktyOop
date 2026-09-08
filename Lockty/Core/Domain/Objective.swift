import Foundation

/// Something you meant to do, and how much of it there is.
///
/// Two litres of water. Ten thousand steps. One walk. An objective is a target with a
/// period attached, and the period is what makes it a habit rather than a note: "two
/// litres" is a wish, "two litres a day" is something you can be behind on.
///
/// Kept in the App Group beside the rules and the frictions, because a friction can ask
/// about them -- "have you had your water yet" is a fair question to be asked by the
/// thing standing between you and TikTok.
nonisolated struct Objective: Codable, Hashable, Identifiable {
    let id: UUID
    var name: String
    /// An SF Symbol. Objectives are read at a glance in a row, and a glyph is faster than
    /// a word at that size.
    var symbolName: String
    /// How much counts as done, in whatever the unit is.
    var target: Double
    /// What one press adds. Two litres of water in eight glasses is a step of 0.25.
    var step: Double
    /// "L", "steps", "min" -- or nothing, for the ones that are simply done or not.
    var unit: String
    var period: ObjectivePeriod
    /// Its colour, from the same six a routine has. An objective is a thing you own, and
    /// the ring is where you recognise it.
    var color: RoutineColor
    /// Where the progress comes from: your own taps, Health, or Screen Time.
    var source: ObjectiveSource
    /// The app this one is about, for `.appUsage`. Nil for every other kind.
    var appID: AppIdentity.ID?
    /// The app's name, kept so the objective can say what it is about without asking
    /// Screen Time -- which will not tell the app, only its extensions.
    var appName: String?
    var createdAt: Date
    var updatedAt: Date

    init(
        id: UUID = UUID(),
        name: String,
        symbolName: String = "target",
        target: Double = 1,
        step: Double = 1,
        unit: String = "",
        period: ObjectivePeriod = .daily,
        color: RoutineColor = .mint,
        source: ObjectiveSource = .manual,
        appID: AppIdentity.ID? = nil,
        appName: String? = nil,
        createdAt: Date = Date(),
        updatedAt: Date = Date()
    ) {
        self.id = id
        self.name = name
        self.symbolName = symbolName
        self.target = max(target, 0.01)
        self.step = max(step, 0.01)
        self.unit = unit
        self.period = period
        self.color = color
        self.source = source
        self.appID = appID
        self.appName = appName
        self.createdAt = createdAt
        self.updatedAt = updatedAt
    }

    /// Whether the target is a ceiling rather than a floor.
    ///
    /// "Under 30 minutes in TikTok" is met while you are below it and lost when you go
    /// past -- the opposite of every other objective, where the number climbs towards
    /// something. It is not a block: nothing is shielded, nothing is refused. It is a
    /// thing you said you would do, kept or not kept like any other.
    nonisolated var staysUnder: Bool {
        source == .appUsage || source == .screenTime || source == .focusScore
    }

    /// Whether this is simply done or not done.
    ///
    /// Not a kind of its own: an objective with a target of one and nothing to measure it
    /// in *is* a yes or a no, and giving it a plus and a minus to walk between zero and
    /// one would be a stepper for a question with two answers.
    nonisolated var isYesNo: Bool {
        source == .manual && target == 1 && unit.isEmpty
    }

    /// Decoded leniently for the colour, which arrived after the first objectives were
    /// written: one saved without it reads as mint rather than failing to load at all.
    nonisolated init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decode(UUID.self, forKey: .id)
        name = try container.decode(String.self, forKey: .name)
        symbolName = try container.decode(String.self, forKey: .symbolName)
        target = try container.decode(Double.self, forKey: .target)
        step = try container.decode(Double.self, forKey: .step)
        unit = try container.decode(String.self, forKey: .unit)
        period = try container.decode(ObjectivePeriod.self, forKey: .period)
        color = try container.decodeIfPresent(RoutineColor.self, forKey: .color) ?? .mint
        source = try container.decodeIfPresent(ObjectiveSource.self, forKey: .source) ?? .manual
        appID = try container.decodeIfPresent(AppIdentity.ID.self, forKey: .appID)
        appName = try container.decodeIfPresent(String.self, forKey: .appName)
        createdAt = try container.decode(Date.self, forKey: .createdAt)
        updatedAt = try container.decode(Date.self, forKey: .updatedAt)
    }

    /// How a value reads for this objective. Whole numbers stay whole: "8 glasses", not
    /// "8.0 glasses".
    nonisolated func format(_ value: Double) -> String {
        if isYesNo { return value >= target ? "Yes" : "Not yet" }
        let number = formatNumber(value)
        return unit.isEmpty ? number : "\(number) \(unit)"
    }

    /// The figure on its own, without what it is measured in.
    ///
    /// For the places that say the unit once and then count in it: a row reading "11,840
    /// steps of 10,000 steps" says "steps" twice and runs off the end of the line, when
    /// the only thing changing in it is the number.
    ///
    /// Grouped, because these are read at a glance: 11,840 is a figure and 11840 is a
    /// string of digits you have to count.
    nonisolated func formatNumber(_ value: Double) -> String {
        let rounded = (value * 100).rounded() / 100
        guard rounded != rounded.rounded() else {
            return Int(rounded).formatted(.number.grouping(.automatic))
        }
        return String(format: "%.2f", rounded)
            .replacingOccurrences(of: "0$", with: "", options: .regularExpression)
    }

    /// What is being aimed at, in one line: "10,000 steps".
    ///
    /// The half of the reading that does not change. It sits under the name so the figure
    /// beside the bar can be the number alone.
    ///
    /// The target and nothing else. It used to carry where the figure comes from as well
    /// -- "Steps · 10,000 steps" -- which is the objective's own name said twice with a
    /// dot in the middle: the row above already reads "Steps".
    nonisolated var goalCaption: String {
        guard !isYesNo else { return "" }
        return staysUnder ? "Under \(format(target))" : format(target)
    }
}

/// Where an objective's progress comes from.
///
/// Some things you count yourself -- glasses of water, walks, pages. Others the phone
/// already counts better than you would: steps and sleep are measured whether or not
/// anybody remembers to tap, and asking someone to log their own step count is asking
/// them to do arithmetic Health has already done.
nonisolated enum ObjectiveSource: String, Codable, CaseIterable, Hashable, Identifiable {
    case manual
    case steps
    case sleep
    /// Minutes in one app, from the day's own Screen Time report -- the same figure the
    /// usage screens show. A ceiling rather than a target: see `Objective.staysUnder`.
    case appUsage
    /// Minutes on the phone altogether, from the same day snapshots as `appUsage`. The
    /// whole of it rather than one app: "under two hours today" is a different promise
    /// from "under thirty minutes in TikTok", and someone who keeps the second by moving
    /// to a third app has kept nothing.
    case screenTime
    /// The day's Focus score, read from the snapshot the app leaves in the App Group --
    /// the same figure the badge on Today shows, so the two cannot disagree.
    case focusScore

    var id: String { rawValue }

    /// What the row calls it. One word each: the row already says "Type", and "Counted
    /// by you" in the value of a field called "Counted by" was the same words twice.
    var title: String {
        switch self {
        case .manual: "Custom"
        case .steps: "Steps"
        case .sleep: "Sleep"
        case .appUsage: "App time"
        case .screenTime: "Screen time"
        case .focusScore: "Focus score"
        }
    }

    /// The line under it, for the menu that offers the three.
    var detail: String {
        switch self {
        case .manual: "You count it"
        case .steps: "Read from Health"
        case .sleep: "Hours asleep, from Health"
        case .appUsage: "Minutes in one app"
        case .screenTime: "Minutes on the phone, all apps"
        case .focusScore: "The score on today's badge"
        }
    }

    /// Whether the value is read rather than tapped. A read objective cannot be advanced
    /// by hand -- there is nothing honest to add.
    var isReadFromHealth: Bool { self == .steps || self == .sleep }

    /// Whether the figure is read rather than tapped, wherever it is read from.
    var isMeasured: Bool { self != .manual }

    /// What such an objective is measured in, and a sensible target to start from.
    var defaultUnit: String {
        switch self {
        case .manual: ""
        case .steps: "steps"
        case .sleep: "h"
        case .appUsage: "min"
        case .screenTime: "min"
        case .focusScore: "%"
        }
    }

    var defaultTarget: Double {
        switch self {
        case .manual: 1
        case .steps: 8000
        case .sleep: 8
        case .appUsage: 30
        case .screenTime: 120
        case .focusScore: 70
        }
    }

    var symbolName: String {
        switch self {
        case .manual: "target"
        case .steps: "figure.walk"
        case .sleep: "bed.double.fill"
        case .appUsage: "hourglass"
        case .screenTime: "iphone"
        case .focusScore: "gauge.medium"
        }
    }
}

nonisolated enum ObjectivePeriod: String, Codable, CaseIterable, Hashable, Identifiable {
    case daily
    case weekly
    case monthly

    var id: String { rawValue }

    var title: String {
        switch self {
        case .daily: "Every day"
        case .weekly: "Every week"
        case .monthly: "Every month"
        }
    }

    /// The word on the segmented picker.
    ///
    /// "Daily", not "Day". The same control on the usage screen means *the range I am
    /// looking at*; here it means *which objectives* -- the ones counted by the day, by
    /// the week, by the month. An adjective says that and a noun does not, and the two
    /// screens should not use the same word for two different jobs.
    var pickerTitle: String {
        switch self {
        case .daily: "Daily"
        case .weekly: "Weekly"
        case .monthly: "Monthly"
        }
    }

    /// The short word for the row: "today", "this week", "this month".
    var currentTitle: String {
        switch self {
        case .daily: "today"
        case .weekly: "this week"
        case .monthly: "this month"
        }
    }

    /// The key progress is filed under. A run of days, a week of the year, a month --
    /// whichever this objective is counted in.
    ///
    /// Written rather than derived from a date range so that progress cannot drift when
    /// the phone changes timezone mid-period: the key for a Tuesday in Madrid and the key
    /// for the same Tuesday in Lisbon are the same string.
    nonisolated func key(for date: Date, calendar: Calendar = .current) -> String {
        let components = calendar.dateComponents([.year, .month, .day, .weekOfYear, .yearForWeekOfYear], from: date)

        switch self {
        case .daily:
            return String(format: "%04d-%02d-%02d", components.year ?? 0, components.month ?? 0, components.day ?? 0)
        case .weekly:
            return String(format: "%04d-W%02d", components.yearForWeekOfYear ?? 0, components.weekOfYear ?? 0)
        case .monthly:
            return String(format: "%04d-%02d", components.year ?? 0, components.month ?? 0)
        }
    }
}

/// What every objective has done in the period it is counted in.
nonisolated struct ObjectiveProgressState: Codable, Hashable {
    /// Objective id, then period key, then how much.
    ///
    /// Health-backed objectives are in here too, but nothing writes them by hand: their
    /// value is read from Health each time the screen loads and put here so that
    /// everything downstream -- the card, the page, the friction, the Focus credit --
    /// reads one place rather than each asking Health its own question.
    var values: [UUID: [String: Double]]

    init(values: [UUID: [String: Double]] = [:]) {
        self.values = values
    }

    static let empty = ObjectiveProgressState()

    nonisolated func value(for objective: Objective, on date: Date = Date()) -> Double {
        values[objective.id]?[objective.period.key(for: date)] ?? 0
    }

    nonisolated func isComplete(_ objective: Objective, on date: Date = Date()) -> Bool {
        let value = value(for: objective, on: date)
        // A ceiling is kept by staying below it, which also means it starts the day kept
        // and can be lost -- unlike everything else here, which starts lost and is won.
        return objective.staysUnder ? value <= objective.target : value >= objective.target
    }

    /// How far along, capped at one so a good day cannot overflow the ring.
    nonisolated func fraction(for objective: Objective, on date: Date = Date()) -> Double {
        guard objective.target > 0 else { return 0 }
        return min(value(for: objective, on: date) / objective.target, 1)
    }

    /// Replaces the period's value outright, for the ones that are read rather than
    /// counted.
    nonisolated mutating func set(_ value: Double, for objective: Objective, on date: Date = Date()) {
        var byPeriod = values[objective.id] ?? [:]
        byPeriod[objective.period.key(for: date)] = max(value, 0)
        values[objective.id] = byPeriod
    }

    nonisolated mutating func add(_ amount: Double, to objective: Objective, on date: Date = Date()) {
        // A weekly or monthly objective is also written under today's date, so the chart
        // can show which days it was moved on. The period key is what everything reads;
        // this is only the record of when.
        if objective.period != .daily {
            let dayKey = ObjectivePeriod.daily.key(for: date)
            var byDay = values[objective.id] ?? [:]
            byDay[dayKey] = max((byDay[dayKey] ?? 0) + amount, 0)
            values[objective.id] = byDay
        }

        let key = objective.period.key(for: date)
        var byPeriod = values[objective.id] ?? [:]
        // Never below nothing, and no ceiling: twenty glasses when you meant to drink
        // fifteen is twenty, and an objective that refused to record it would be telling
        // you what you did.
        byPeriod[key] = max((byPeriod[key] ?? 0) + amount, 0)
        values[objective.id] = byPeriod
    }

    /// How far back the history goes.
    ///
    /// Ninety days of keys per objective: enough for a month chart and the fortnight
    /// behind it, and small enough that the file stays a few kilobytes. Older keys are
    /// dropped rather than kept for ever -- nobody is going to ask what they drank in
    /// March, and a file that only grows is a file that eventually costs something.
    static let historyDays = 90

    /// The daily figures behind an objective, oldest first.
    ///
    /// Days with nothing recorded come back as zero rather than being left out: a chart
    /// of "how much each day" needs the empty days, because an empty day is the finding.
    nonisolated func dailyValues(
        for objective: Objective,
        days: Int,
        endingOn date: Date = Date(),
        calendar: Calendar = .current
    ) -> [(date: Date, value: Double)] {
        let byPeriod = values[objective.id] ?? [:]

        return stride(from: days - 1, through: 0, by: -1).compactMap { offset in
            guard let day = calendar.date(byAdding: .day, value: -offset, to: date) else { return nil }
            return (day, byPeriod[ObjectivePeriod.daily.key(for: day, calendar: calendar)] ?? 0)
        }
    }

    /// Drops objectives that no longer exist and keys older than the history window.
    ///
    /// The current period is what everything reads; the rest is what the charts are drawn
    /// from. Both are kept, which is the change: this used to keep only today, so a week
    /// view had nothing behind it to show.
    nonisolated mutating func prune(keeping objectives: [Objective], on date: Date = Date()) {
        let calendar = Calendar.current
        let horizon = calendar.date(byAdding: .day, value: -Self.historyDays, to: date) ?? date
        let ids = Set(objectives.map(\.id))

        // Every key still worth keeping: the ninety days behind us, plus the current
        // week and month, which are named differently and would not match a day key.
        var living = Set<String>()
        for offset in 0...Self.historyDays {
            guard let day = calendar.date(byAdding: .day, value: -offset, to: date) else { continue }
            guard day >= horizon else { continue }
            living.insert(ObjectivePeriod.daily.key(for: day, calendar: calendar))
            living.insert(ObjectivePeriod.weekly.key(for: day, calendar: calendar))
            living.insert(ObjectivePeriod.monthly.key(for: day, calendar: calendar))
        }

        values = values
            .filter { ids.contains($0.key) }
            .mapValues { $0.filter { living.contains($0.key) } }
    }
}
