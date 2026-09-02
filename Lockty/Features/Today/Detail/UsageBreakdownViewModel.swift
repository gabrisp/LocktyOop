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

    private let builder: UsageBreakdownBuilder
    private let classificationRepository: AppClassificationRepository
    private let calendar: Calendar

    init(
        day: Date,
        classificationRepository: AppClassificationRepository,
        builder: UsageBreakdownBuilder = UsageBreakdownBuilder(),
        calendar: Calendar = .current
    ) {
        var calendar = calendar
        calendar.firstWeekday = 2
        self.calendar = calendar
        self.anchorDay = calendar.startOfDay(for: day)
        self.classificationRepository = classificationRepository
        self.builder = builder
        self.breakdown = .empty(period: .day, anchorDay: day)
    }

    /// Moves an app to the next classification, and puts it in its new section.
    ///
    /// Cycled rather than picked from a menu: there are three, they have an order --
    /// productive, neutral, distracting -- and a menu for three values is three taps
    /// where one would do.
    func cycleClassification(of app: UsageBreakdownApp) async {
        let next: AppClassification = switch app.classification {
        case .productive: .neutral
        case .neutral: .unproductive
        case .unproductive: .productive
        }

        await classificationRepository.saveClassification(next, for: app.app.id)
        await reload()
    }

    func reload() async {
        let classifications = await classificationRepository.allClassifications()
        let next = builder.breakdown(
            period: period,
            anchorDay: anchorDay,
            classifications: classifications,
            calendar: calendar
        )
        withAnimation(.smooth(duration: 0.3)) { breakdown = next }
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

    var deltaCaption: String {
        switch period {
        case .day: "less than the day before"
        case .week: "less a day than last week"
        case .month: "less a day than last month"
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
