import SwiftUI

/// The day in twenty-four bars, each cut into what the hour went to.
///
/// The pulse card's chart without the card and without the tabs. The tabs were three
/// charts sharing one axis, and only one of the three answers a question worth a picture:
/// how the time divided. Unlocks and notifications are counts -- they are already said
/// exactly, in a line, on the same page, and drawing eighty-two of something as bars adds
/// nothing to knowing it was eighty-two.
///
/// The card is gone too. This sits inside a section that already has a heading, and a
/// card inside a section is a box inside a box.
struct DailyDistributionChart: View {
    let state: HourlyActivityState
    /// The day this is a picture of, so the hours that have not happened yet can be told
    /// apart from the hours you did not spend on your phone. Two very different silences.
    var day: Date = Date()
    var height: CGFloat = 150

    /// Which hour a finger is resting on. The chart is read by dragging along it, which
    /// is the only way twenty-four values fit in a strip this wide and stay legible.
    @State private var focusedHour: Int?

    /// The tallest hour, which the bars are drawn against. A minimum of ten minutes so a
    /// nearly-empty day does not turn one four-minute hour into a full-height bar.
    private var axisMaximum: TimeInterval {
        max(state.hours.map(\.usage).max() ?? 0, 10 * 60)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: LocktySpacing.md) {
            chart

            legend
        }
    }

    /// The last hour that has actually happened. Everything past it on today's chart is
    /// a bar for an hour nobody has lived yet.
    private var lastElapsedHour: Int {
        guard Calendar.current.isDateInToday(day) else { return 23 }
        return Calendar.current.component(.hour, from: Date())
    }

    private var chart: some View {
        VStack(alignment: .leading, spacing: 6) {
            GeometryReader { proxy in
                let columnWidth = proxy.size.width / 24

                ZStack(alignment: .bottom) {
                    gridlines(height: proxy.size.height)

                    HStack(alignment: .bottom, spacing: 0) {
                        ForEach(state.hours) { hour in
                            column(hour, plotHeight: proxy.size.height)
                                .frame(width: columnWidth)
                        }
                    }

                    if let focusedHour {
                        tooltip(for: focusedHour)
                            .frame(width: proxy.size.width, alignment: .leading)
                            .offset(
                                x: tooltipOffset(for: focusedHour, columnWidth: columnWidth, width: proxy.size.width),
                                y: -(proxy.size.height - 36)
                            )
                            .transition(.blurReplace)
                    }
                }
                .contentShape(Rectangle())
                .gesture(
                    DragGesture(minimumDistance: 0)
                        .onChanged { value in
                            let index = Int(value.location.x / max(columnWidth, 1))
                            focusedHour = min(max(index, 0), 23)
                        }
                        .onEnded { _ in
                            withAnimation(.smooth(duration: 0.2)) { focusedHour = nil }
                        }
                )
            }
            .frame(height: height)
            // One tick per column crossed, so the day can be felt as well as read.
            .sensoryFeedback(.selection, trigger: focusedHour)

            hourLabels
        }
    }

    /// The reading for the hour under the finger.
    ///
    /// Kept from the card this chart came out of. Twenty-four bars in a strip this wide
    /// can only ever show the shape of a day; the exact figure for one hour has to be
    /// asked for, and this is how you ask.
    private func tooltip(for hour: Int) -> some View {
        VStack(spacing: 2) {
            Text(String(format: "%d:00 - %d:00", hour, (hour + 1) % 24))
                .font(.system(.footnote, design: .default, weight: .regular))
                .foregroundStyle(LocktyColors.secondaryText)

            Text(state.hours[hour].usage > 0
                 ? LocktyDurationFormatter.abbreviated(state.hours[hour].usage)
                 : (hour > lastElapsedHour ? "Not yet" : "Nothing"))
                .font(.system(.headline, design: .default, weight: .semibold))
                .foregroundStyle(LocktyColors.primaryText)
                .monospacedDigit()
                .contentTransition(.numericText())

            if state.hours[hour].classifiedTotal > 0 {
                HStack(spacing: LocktySpacing.sm) {
                    splitLabel(state.hours[hour].unproductive, color: LocktyColors.unproductive)
                    splitLabel(state.hours[hour].productive, color: LocktyColors.productive)
                }
                .padding(.top, 2)
            }
        }
        .padding(.horizontal, LocktySpacing.md)
        .padding(.vertical, LocktySpacing.sm)
        // Glass, like everything in the app that floats over something else: the bars
        // underneath stay faintly there, which matters because it is about one of them.
        .safeGlass(radius: 16)
        .locktyImperfectBorder(RoundedRectangle(cornerRadius: 16, style: .continuous))
        .fixedSize()
        .allowsHitTesting(false)
    }

    @ViewBuilder
    private func splitLabel(_ value: TimeInterval, color: Color) -> some View {
        if value > 0 {
            HStack(spacing: 3) {
                Circle()
                    .fill(color)
                    .frame(width: 6, height: 6)

                Text(LocktyDurationFormatter.abbreviated(value))
                    .font(.system(.caption, design: .default, weight: .semibold))
                    .foregroundStyle(color)
                    .monospacedDigit()
                    .contentTransition(.numericText())
            }
        }
    }

    /// Keeps the tooltip on the chart. Following the finger exactly walks it off both
    /// ends, where it is cut in half by the edge of the screen.
    private func tooltipOffset(for hour: Int, columnWidth: CGFloat, width: CGFloat) -> CGFloat {
        let centre = columnWidth * (CGFloat(hour) + 0.5)
        let tooltipWidth: CGFloat = 128
        return min(max(centre - tooltipWidth / 2, 0), max(width - tooltipWidth, 0))
    }

    private func column(_ hour: HourlyActivityState.Hour, plotHeight: CGFloat) -> some View {
        let ratio = axisMaximum > 0 ? min(hour.usage / axisMaximum, 1) : 0
        let barHeight = max(CGFloat(ratio) * plotHeight, hour.usage > 0 ? 3 : 0)
        // An hour that has not come round yet is not an empty hour. Its track is faded
        // rather than drawn at full strength, so the day reads as unfinished instead of
        // as one that went quiet at two in the afternoon.
        let isFuture = hour.hour > lastElapsedHour
        let isFocused = focusedHour == hour.hour

        return ZStack(alignment: .bottom) {
            Capsule(style: .continuous)
                .fill(LocktyColors.ink(0.06))
                .frame(height: plotHeight)
                .opacity(isFuture ? 0.3 : 1)

            // Productive at the bottom, then neutral, then unproductive on top -- so the
            // red caps line up across the day at the tops of the bars and read as a row
            // rather than having to be hunted for inside each one.
            VStack(spacing: 0) {
                piece(hour.unproductive, of: hour.classifiedTotal, height: barHeight, color: LocktyColors.unproductive)
                piece(hour.neutral, of: hour.classifiedTotal, height: barHeight, color: LocktyColors.neutral)
                piece(hour.productive, of: hour.classifiedTotal, height: barHeight, color: LocktyColors.productive)
            }
            .frame(height: barHeight)
            // Masked rather than clipped square: the bar keeps its rounded ends and the
            // pieces inside follow them.
            .mask { Capsule(style: .continuous).frame(height: barHeight) }
            .opacity(isFocused ? 1 : 0.72)
        }
        .frame(width: 7)
        .frame(maxWidth: .infinity)
        .animation(.snappy(duration: 0.3), value: barHeight)
    }

    @ViewBuilder
    private func piece(
        _ value: TimeInterval,
        of total: TimeInterval,
        height: CGFloat,
        color: Color
    ) -> some View {
        if value > 0, total > 0 {
            color.frame(height: height * CGFloat(value / total))
        }
    }

    private func gridlines(height: CGFloat) -> some View {
        VStack(spacing: 0) {
            ForEach(0..<3, id: \.self) { index in
                Rectangle()
                    .fill(LocktyColors.separator.opacity(0.3))
                    .frame(height: 1)

                if index < 2 { Spacer(minLength: 0) }
            }
        }
        .frame(height: height)
        .allowsHitTesting(false)
    }

    /// Midnight, six, noon, six -- the quarters of the day, which is as much as a strip
    /// this wide can name without the numbers touching.
    private var hourLabels: some View {
        GeometryReader { proxy in
            let columnWidth = proxy.size.width / 24

            ForEach([0, 6, 12, 18], id: \.self) { hour in
                Text("\(hour)")
                    .font(.system(.caption2, design: .default, weight: .regular))
                    .foregroundStyle(LocktyColors.tertiaryText)
                    .monospacedDigit()
                    .offset(x: columnWidth * CGFloat(hour) + 2)
            }
        }
        .frame(height: 14)
    }

    /// What the three colours mean, with how much of the day each one took.
    ///
    /// The totals are in it because a legend that only names colours is a legend you read
    /// once and never again -- with the figures beside them it is the summary of the
    /// chart, and the chart is the shape of it through the day.
    private var legend: some View {
        HStack(spacing: LocktySpacing.lg) {
            entry("Productive", total: state.hours.reduce(0) { $0 + $1.productive }, color: LocktyColors.productive)
            entry("Neutral", total: state.hours.reduce(0) { $0 + $1.neutral }, color: LocktyColors.neutral)
            entry("Distracting", total: state.hours.reduce(0) { $0 + $1.unproductive }, color: LocktyColors.unproductive)

            Spacer(minLength: 0)
        }
    }

    private func entry(_ title: String, total: TimeInterval, color: Color) -> some View {
        HStack(spacing: 6) {
            Capsule(style: .continuous)
                .fill(color)
                .frame(width: 8, height: 8)

            VStack(alignment: .leading, spacing: 1) {
                Text(title)
                    .font(.system(.caption2, design: .default, weight: .regular))
                    .foregroundStyle(LocktyColors.tertiaryText)

                Text(total > 0 ? LocktyDurationFormatter.abbreviated(total) : "--")
                    .font(.system(.footnote, design: .default, weight: .semibold))
                    .foregroundStyle(LocktyColors.primaryText)
                    .monospacedDigit()
                    .contentTransition(.numericText())
            }
        }
    }
}
