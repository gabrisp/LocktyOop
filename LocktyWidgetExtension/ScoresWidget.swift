import SwiftUI
import WidgetKit

/// The day's three scores, on the home screen.
///
/// Focus and Detox either side of a ring, with Checks and the day's screen time as the
/// smaller figures under them: the shape of a fitness card, because it is the same kind of
/// reading -- two headline numbers you are trying to move, a couple of raw ones that
/// explain them, and the rings that say how far round each has got.
///
/// It reads a photograph, not the truth. The scores come out of Core Data, Screen Time and
/// a stack of calculators the widget cannot reach, so the app writes the finished figures
/// to the App Group each time it works them out and this draws whatever was left there.
struct ScoresWidget: Widget {
    var body: some WidgetConfiguration {
        StaticConfiguration(kind: DailyScoreWidgets.kind, provider: ScoresTimelineProvider()) { entry in
            ScoresWidgetView(entry: entry)
                .containerBackground(for: .widget) { LocktyColors.background }
        }
        .configurationDisplayName("Today's scores")
        .description("Focus, Detox and Checks at a glance.")
        // Medium only: three scores and two figures need the width, and squeezed into a
        // square they stop being readable at arm's length, which is the whole job.
        .supportedFamilies([.systemMedium])
    }
}

struct ScoresEntry: TimelineEntry {
    let date: Date
    let snapshot: DailyScoreSnapshot?

    /// Whether what was left in the App Group is about today. A yesterday's snapshot is
    /// not today's answer, and showing it unlabelled is worse than showing nothing.
    var isCurrent: Bool {
        snapshot?.day == DayKey(date: Date()).id
    }
}

struct ScoresTimelineProvider: TimelineProvider {
    func placeholder(in context: Context) -> ScoresEntry {
        ScoresEntry(date: Date(), snapshot: nil)
    }

    func getSnapshot(in context: Context, completion: @escaping (ScoresEntry) -> Void) {
        completion(entry())
    }

    /// One entry, refreshed on the hour.
    ///
    /// The app reloads this the moment it recomputes the day, which is the update that
    /// matters. The hourly entry is only so a phone left alone all afternoon does not sit
    /// on a figure from breakfast.
    func getTimeline(in context: Context, completion: @escaping (Timeline<ScoresEntry>) -> Void) {
        let next = Date().addingTimeInterval(60 * 60)
        completion(Timeline(entries: [entry()], policy: .after(next)))
    }

    private func entry() -> ScoresEntry {
        ScoresEntry(date: Date(), snapshot: AppGroupStore().loadDailyScores())
    }
}

struct ScoresWidgetView: View {
    let entry: ScoresEntry

    private var focus: DailyScoreSnapshot.Score? { entry.snapshot?.score("focus") }
    private var detox: DailyScoreSnapshot.Score? { entry.snapshot?.score("detox") }
    private var checks: DailyScoreSnapshot.Score? { entry.snapshot?.score("checks") }

    var body: some View {
        if entry.snapshot == nil {
            empty
        } else {
            HStack(spacing: 10) {
                column(
                    headline: focus,
                    tint: LocktyColors.productive,
                    secondaryTitle: checks?.title.uppercased() ?? "CHECKS",
                    secondaryValue: checks?.displayValue ?? "--",
                    alignment: .trailing
                )

                rings

                column(
                    headline: detox,
                    tint: LocktyColors.routine(.sky),
                    secondaryTitle: "SCREEN TIME",
                    secondaryValue: screenTimeText,
                    alignment: .leading
                )
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
    }

    /// One side: the score in its own colour, its name under it, and a quieter figure
    /// below that -- the raw number the score was made from.
    private func column(
        headline: DailyScoreSnapshot.Score?,
        tint: Color,
        secondaryTitle: String,
        secondaryValue: String,
        alignment: HorizontalAlignment
    ) -> some View {
        VStack(alignment: alignment, spacing: 0) {
            Text(headline?.displayValue ?? "--")
                .font(.system(size: 30, weight: .bold))
                .foregroundStyle(tint)
                .monospacedDigit()
                .lineLimit(1)
                .minimumScaleFactor(0.6)

            Text((headline?.title ?? "").uppercased())
                .font(.system(size: 12, weight: .heavy))
                .foregroundStyle(tint)
                .lineLimit(1)
                .minimumScaleFactor(0.7)

            Spacer(minLength: 8)

            Text(secondaryTitle)
                .font(.system(size: 11, weight: .heavy))
                .foregroundStyle(LocktyColors.tertiaryText)
                .lineLimit(1)

            Text(secondaryValue)
                .font(.system(size: 17, weight: .semibold))
                .foregroundStyle(LocktyColors.secondaryText)
                .monospacedDigit()
                .lineLimit(1)
                .minimumScaleFactor(0.7)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: alignment == .leading ? .leading : .trailing)
    }

    /// The three rims, one inside the next. Each is its own score: nothing is stacked or
    /// averaged, so a full outer ring and an empty inner one is exactly what it looks like.
    private var rings: some View {
        ZStack {
            ring(focus?.progress ?? 0, tint: LocktyColors.productive, inset: 0)
            ring(detox?.progress ?? 0, tint: LocktyColors.routine(.sky), inset: 11)
            ring(checks?.progress ?? 0, tint: LocktyColors.warning, inset: 22)
        }
        .frame(width: 104, height: 104)
    }

    private func ring(_ progress: Double, tint: Color, inset: CGFloat) -> some View {
        ZStack {
            Circle()
                .stroke(LocktyColors.ink(0.10), lineWidth: 7)

            Circle()
                .trim(from: 0, to: max(min(progress, 1), 0.01))
                .stroke(tint, style: StrokeStyle(lineWidth: 7, lineCap: .round))
                .rotationEffect(.degrees(-90))
        }
        .padding(inset)
    }

    private var screenTimeText: String {
        guard let seconds = entry.snapshot?.screenTime else { return "--" }
        let minutes = Int(seconds / 60)
        guard minutes >= 60 else { return "\(minutes)m" }
        return "\(minutes / 60)h \(minutes % 60)m"
    }

    private var empty: some View {
        VStack(spacing: 6) {
            Image(systemName: "chart.bar")
                .font(.system(size: 20, weight: .regular))
                .foregroundStyle(LocktyColors.secondaryText)

            Text("Open Lockty to read today")
                .font(.system(.footnote, design: .default, weight: .regular))
                .foregroundStyle(LocktyColors.secondaryText)
                .multilineTextAlignment(.center)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}
