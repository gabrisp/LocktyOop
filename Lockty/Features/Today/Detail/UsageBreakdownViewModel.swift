import Combine
import Foundation
import SwiftUI

@MainActor
final class UsageBreakdownViewModel: ObservableObject {
    @Published var period: UsagePeriod = .day
    @Published var anchorDay: Date
    @Published var isChoosingPeriod = false
    /// Whether the list is being reclassified rather than read.
    ///
    /// The whole screen turns on what each app is called -- productive, distracting,
    /// neutral -- and until now that could only be changed somewhere else, which meant
    /// noticing a wrong label here and having to go and find where to fix it.
    @Published var isEditing = false
    @Published private(set) var breakdown: UsageBreakdown
    /// Every app there is data for, which is what the grid offers.
    @Published private(set) var knownApps: [UsageBreakdownApp] = []

    /// The days behind the period on screen, for the trend line.
    @Published private(set) var trend: [DailyTrendPoint] = []

    private let builder: UsageBreakdownBuilder
    private let trendBuilder = DailyTrendBuilder()
    private let classificationRepository: AppClassificationRepository
    private let autoFocusManager: AutoFocusManager?
    private let calendar: Calendar

    init(
        day: Date,
        classificationRepository: AppClassificationRepository,
        autoFocusManager: AutoFocusManager? = nil,
        builder: UsageBreakdownBuilder = UsageBreakdownBuilder(),
        calendar: Calendar = .current
    ) {
        self.autoFocusManager = autoFocusManager
        var calendar = calendar
        calendar.firstWeekday = 2
        self.calendar = calendar
        self.anchorDay = calendar.startOfDay(for: day)
        self.classificationRepository = classificationRepository
        self.builder = builder
        self.breakdown = .empty(period: .day, anchorDay: day)
    }

    /// Files an app under a classification, and puts it in its new section.
    ///
    /// The distracting list is updated with it. This screen is where apps actually get
    /// filed now, and it was only writing the classification -- so calling something
    /// unproductive here coloured its row and left the thing that watches distracting
    /// apps watching nothing.
    func setClassification(_ classification: AppClassification, of app: UsageBreakdownApp) async {
        guard classification != app.classification else { return }
        await classificationRepository.saveClassification(classification, for: app.app.id)
        await autoFocusManager?.updateMembership(for: app.app, classification: classification)
        await reload()
    }

    /// Rebuilds the screen off the main actor.
    ///
    /// Everything here is file reading and JSON decoding -- a month is thirty-one days
    /// read for the period and thirty-one more for the one before it -- and it was all
    /// happening on the main actor, so the screen was blocked for exactly as long as the
    /// disk took. The building is done on a background task and only the finished value
    /// comes back.
    func reload() async {
        let classifications = await classificationRepository.allClassifications()
        let period = period
        let anchorDay = anchorDay
        let calendar = calendar
        let builder = builder

        let next = await Task.detached(priority: .userInitiated) {
            builder.breakdown(
                period: period,
                anchorDay: anchorDay,
                classifications: classifications,
                calendar: calendar
            )
        }.value

        withAnimation(.smooth(duration: 0.3)) {
            breakdown = next
        }

        await reloadTrend()

        // The grid of every app ever seen is another month of reads, and it is only ever
        // looked at in edit mode. It used to be built on every single load of a screen
        // most people never edit.
        if isEditing {
            await loadKnownApps(classifications: classifications)
        }
    }

    /// How many days a period's trend line needs before it is worth drawing.
    ///
    /// A week means a week. Three days of data drawn across a week-shaped axis is a line
    /// that says something about your week which is not true of your week -- so until
    /// there is a full one the chart is shown blurred, with the days still to go named.
    /// The month is a fortnight rather than thirty-one days: a month-long wait for a
    /// first chart is a chart nobody sees, and a fortnight is already a shape.
    var trendMinimumDays: Int {
        switch period {
        case .day: 0
        case .week: 7
        case .month: 14
        }
    }

    var hasEnoughTrendHistory: Bool {
        trend.count >= trendMinimumDays
    }

    /// What is missing, said as a wait rather than as a refusal.
    var trendWaitCaption: String {
        let remaining = max(trendMinimumDays - trend.count, 1)
        let unit = remaining == 1 ? "1 more day" : "\(remaining) more days"
        return "Your line starts with a full \(period == .week ? "week" : "fortnight"). Come back in \(unit)."
    }

    private func reloadTrend() async {
        guard period != .day else {
            trend = []
            return
        }

        let builder = trendBuilder
        let anchorDay = anchorDay
        let days = period == .week ? 7 : 30

        let next = await Task.detached(priority: .userInitiated) {
            builder.trend(endingOn: anchorDay, days: days)
        }.value

        withAnimation(.smooth(duration: 0.35)) { trend = next }
    }

    /// The apps the edit grid offers, built the first time editing is entered.
    func loadKnownAppsIfNeeded() async {
        guard knownApps.isEmpty else { return }
        await loadKnownApps(classifications: await classificationRepository.allClassifications())
    }

    private func loadKnownApps(classifications: [AppIdentity.ID: AppClassification]) async {
        let builder = builder
        let calendar = calendar

        let known = await Task.detached(priority: .userInitiated) {
            builder.knownApps(classifications: classifications, calendar: calendar)
        }.value

        withAnimation(.smooth(duration: 0.3)) {
            knownApps = known
        }
    }

    /// The longest single app in the period, which every bar is drawn against.
    ///
    /// One scale for the whole screen rather than one per section: bars that reset at
    /// each heading would draw the largest neutral app the same width as the largest
    /// distracting one, which is the opposite of what a bar is for.
    var longestDuration: TimeInterval {
        breakdown.sections
            .flatMap(\.apps)
            .map(\.duration)
            .max() ?? 0
    }

    var totalCaption: String {
        guard period != .day, breakdown.daysWithData > 0 else { return period.totalCaption }
        // Said out loud, because an average over three days of a month is not a month.
        let days = breakdown.daysWithData
        return "\(period.totalCaption) · \(days == 1 ? "1 day" : "\(days) days")"
    }

    /// The sentence beside the delta, which has to know which way the delta went.
    ///
    /// It used to be fixed on the period alone -- always "less than the day before" --
    /// while the arrow and the colour beside it flipped with the sign. So a day an hour
    /// and three quarters *heavier* than yesterday was drawn in red, with the arrow
    /// pointing up, saying "1 h 44 m less than the day before".
    var deltaCaption: String {
        let isLighter = (breakdown.deltaVersusPrevious ?? 0) >= 0
        switch period {
        case .day: return isLighter ? "less than the day before" : "more than the day before"
        case .week: return isLighter ? "less a day than last week" : "more a day than last week"
        case .month: return isLighter ? "less a day than last month" : "more a day than last month"
        }
    }

    /// What the toolbar says the screen is showing.
    var periodTitle: String {
        let formatter = DateFormatter()
        formatter.calendar = calendar
        formatter.locale = .current

        switch period {
        case .day:
            if calendar.isDateInToday(anchorDay) { return "Today" }
            if calendar.isDateInYesterday(anchorDay) { return "Yesterday" }
            formatter.setLocalizedDateFormatFromTemplate("d MMM")
            return formatter.string(from: anchorDay)

        case .week:
            guard let interval = calendar.dateInterval(of: .weekOfYear, for: anchorDay) else { return "This week" }
            if interval.contains(Date()) { return "This week" }
            formatter.setLocalizedDateFormatFromTemplate("d MMM")
            let end = calendar.date(byAdding: .day, value: 6, to: interval.start) ?? interval.end
            return "\(formatter.string(from: interval.start)) – \(formatter.string(from: end))"

        case .month:
            if calendar.isDate(anchorDay, equalTo: Date(), toGranularity: .month) { return "This month" }
            formatter.setLocalizedDateFormatFromTemplate("MMMM")
            return formatter.string(from: anchorDay)
        }
    }
}
