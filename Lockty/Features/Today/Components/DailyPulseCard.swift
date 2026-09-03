import SwiftUI

/// The day at a glance: three numbers across the top, and the hours behind whichever one
/// is chosen.
///
/// The three sit on one axis rather than in three cards because they are the same day
/// told from three sides -- time spent, times picked up, times interrupted -- and moving
/// between them is more useful than reading them stacked down a screen. Choosing one
/// swaps the chart under it; the bars are hours, and dragging along them reads out the
/// hour under your finger.
struct DailyPulseCard: View {
    let state: HourlyActivityState
    @Binding var metric: HourlyActivityMetric

    /// Which hour the finger is on, or nil when it is not on the chart.
    @State private var focusedHour: Int?

    private var radius: CGFloat { LocktyRadius.medium }

    var body: some View {
        CardView(radius: radius, padding: LocktySpacing.lg) {
            VStack(spacing: LocktySpacing.lg) {
                header
                chart
            }
            .padding(.top, LocktySpacing.sm)
        }
        // One haptic per hour crossed, not per touch event: the drag reports continuously
        // and a tick on every frame is a buzz, where a tick per column is the chart being
        // read.
        .sensoryFeedback(.selection, trigger: focusedHour)
        .animation(.snappy(duration: 0.3), value: metric)
    }

    // MARK: - Header

    private var header: some View {
        HStack(spacing: 0) {
            ForEach(Array(HourlyActivityMetric.allCases.enumerated()), id: \.element) { index, kind in
                if index > 0 {
                    // A hairline, not a gap: three numbers with nothing between them read
                    // as one sentence.
                    Rectangle()
                        .fill(LocktyColors.separator.opacity(0.5))
                        .frame(width: 1, height: 26)
                }

                headerCell(kind)
            }
        }
    }

    private func headerCell(_ kind: HourlyActivityMetric) -> some View {
        Button {
            withAnimation(.snappy(duration: 0.3)) {
                metric = kind
                focusedHour = nil
            }
        } label: {
            VStack(spacing: 4) {
                Text(kind.title)
                    .font(.system(.subheadline, design: .default, weight: .semibold))
                    .foregroundStyle(metric == kind ? LocktyColors.primaryText : LocktyColors.secondaryText)
                    .lineLimit(1)
                    .minimumScaleFactor(0.8)

                HStack(spacing: 3) {
                    // The arrow belongs to reduction alone: it is the only one of the
                    // three that is a comparison rather than a count, and the only one
                    // where a direction means anything.
                    if kind == .reduction, let reduction = state.reductionVersusBaseline {
                        Image(systemName: reduction >= 0 ? "arrowtriangle.down.fill" : "arrowtriangle.up.fill")
                            .font(.system(size: 10, weight: .bold))
                            .foregroundStyle(reduction >= 0 ? LocktyColors.productive : LocktyColors.unproductive)
                    }

                    Text(headlineText(kind))
                        .font(.system(size: 24, weight: .bold))
                        .foregroundStyle(LocktyColors.primaryText)
                        .monospacedDigit()
                        .contentTransition(.numericText())
                        .lineLimit(1)
                        .minimumScaleFactor(0.7)
                }
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, LocktySpacing.sm)
            .padding(.horizontal, LocktySpacing.xs)
            .background {
                if metric == kind {
                    RoundedRectangle(cornerRadius: 18, style: .continuous)
                        .fill(tint(for: kind).opacity(0.16))
                }
            }
            .contentShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
        }
        .buttonStyle(.locktyRow)
        .tappable()
    }

    private func headlineText(_ kind: HourlyActivityMetric) -> String {
        switch kind {
        case .reduction:
            guard let reduction = state.reductionVersusBaseline else { return "--" }
            return LocktyDurationFormatter.abbreviated(abs(reduction))
        case .unlocks:
            return "\(state.totalUnlocks)"
        case .notifications:
            return "\(state.totalNotifications)"
        }
    }

    /// One colour per metric, so the chart says which of the three it is showing without
    /// having to be labelled again underneath the header that already said so.
    private func tint(for kind: HourlyActivityMetric) -> Color {
        switch kind {
        case .reduction: LocktyColors.productive
        case .unlocks: LocktyColors.neutral
        case .notifications: LocktyColors.warning
        }
    }

    // MARK: - Chart

    private var values: [Double] {
        state.hours.map { hour in
            switch metric {
            case .reduction: hour.usage
            case .unlocks: Double(hour.unlocks)
            case .notifications: Double(hour.notifications)
            }
        }
    }

    /// The top of the axis: the tallest hour, rounded up to something a label can say.
    private var axisMaximum: Double {
        let peak = values.max() ?? 0
        guard peak > 0 else { return metric == .reduction ? 3600 : 10 }
        switch metric {
        case .reduction:
            // To the next half hour, so the gridline is always a round clock figure.
            return (peak / 1800).rounded(.up) * 1800
        case .unlocks, .notifications:
            let step: Double = peak <= 10 ? 5 : 10
            return (peak / step).rounded(.up) * step
        }
    }

    private var chart: some View {
        HStack(alignment: .top, spacing: LocktySpacing.sm) {
            bars
            axisLabels
        }
        .frame(height: 168)
    }

    private var bars: some View {
        GeometryReader { proxy in
            let columnWidth = proxy.size.width / 24
            let plotHeight = proxy.size.height - 22

            ZStack(alignment: .topLeading) {
                gridlines(height: plotHeight)

                HStack(alignment: .bottom, spacing: 0) {
                    ForEach(state.hours) { hour in
                        column(hour: hour.hour, plotHeight: plotHeight)
                            .frame(width: columnWidth)
                    }
                }
                .frame(height: plotHeight, alignment: .bottom)

                hourLabels
                    .frame(width: proxy.size.width, height: 20, alignment: .topLeading)
                    .offset(y: plotHeight + 2)

                if let focusedHour {
                    tooltip(for: focusedHour)
                        .frame(width: proxy.size.width, alignment: .leading)
                        .offset(
                            x: tooltipOffset(for: focusedHour, columnWidth: columnWidth, width: proxy.size.width),
                            y: -6
                        )
                        .transition(.blurReplace.combined(with: .opacity))
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
    }

    /// One column: the track it could reach, and the part of it that it did.
    ///
    /// The track is drawn whatever the hour holds. Without it an empty morning is blank
    /// space, and the chart looks like it starts at ten o'clock rather than at midnight.
    private func column(hour: Int, plotHeight: CGFloat) -> some View {
        let value = values[hour]
        let ratio = axisMaximum > 0 ? min(value / axisMaximum, 1) : 0
        let isFocused = focusedHour == hour
        let barHeight = max(CGFloat(ratio) * plotHeight, value > 0 ? 3 : 0)

        return ZStack(alignment: .bottom) {
            Capsule(style: .continuous)
                .fill(LocktyColors.ink(0.06))
                .frame(height: plotHeight)

            // On the reduction tab the bar is an hour of screen time, and an hour is not
            // one thing: the same forty minutes is a different day depending on what it
            // went to. The capsule becomes a mask over the split, so the shape stays a
            // bar and the colour inside it says what the hour was.
            if metric == .reduction, state.hours[hour].classifiedTotal > 0 {
                classifiedFill(state.hours[hour], height: barHeight, isFocused: isFocused)
            } else {
                Capsule(style: .continuous)
                    .fill(isFocused ? tint(for: metric) : tint(for: metric).opacity(0.55))
                    .frame(height: barHeight)
            }
        }
        .frame(width: 7)
        .frame(maxWidth: .infinity)
        .animation(.snappy(duration: 0.3), value: barHeight)
    }

    /// One bar, cut into its parts.
    ///
    /// Productive at the bottom, then neutral, then unproductive on top -- so the red
    /// caps line up across the day at the tops of the bars and can be read as a row
    /// rather than hunted for inside each one.
    private func classifiedFill(
        _ hour: HourlyActivityState.Hour,
        height: CGFloat,
        isFocused: Bool
    ) -> some View {
        let total = hour.classifiedTotal
        let opacity = isFocused ? 1.0 : 0.62

        return VStack(spacing: 0) {
            piece(hour.unproductive, of: total, height: height, color: LocktyColors.unproductive)
            piece(hour.neutral, of: total, height: height, color: LocktyColors.neutral)
            piece(hour.productive, of: total, height: height, color: LocktyColors.productive)
        }
        .frame(height: height)
        .opacity(opacity)
        // Masked, not clipped to a rectangle: the bar keeps its rounded ends and the
        // pieces inside follow them instead of being cut off square at the top.
        .mask {
            Capsule(style: .continuous)
                .frame(height: height)
        }
        .animation(.snappy(duration: 0.3), value: height)
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
                    .fill(LocktyColors.separator.opacity(0.35))
                    .frame(height: 1)

                if index < 2 { Spacer(minLength: 0) }
            }
        }
        .frame(height: height)
        .allowsHitTesting(false)
    }

    /// Midnight, six, noon, six -- the quarters of the day, which is as much as a strip
    /// this wide can label without the numbers touching.
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
        .allowsHitTesting(false)
    }

    private var axisLabels: some View {
        VStack(alignment: .leading, spacing: 0) {
            ForEach(Array([1.0, 0.5, 0.0].enumerated()), id: \.offset) { index, fraction in
                Text(axisLabel(fraction))
                    .font(.system(.caption2, design: .default, weight: .regular))
                    .foregroundStyle(LocktyColors.tertiaryText)
                    .monospacedDigit()
                    .lineLimit(1)

                if index < 2 { Spacer(minLength: 0) }
            }
        }
        .frame(height: 146, alignment: .top)
        .allowsHitTesting(false)
    }

    private func axisLabel(_ fraction: Double) -> String {
        let value = axisMaximum * fraction
        switch metric {
        case .reduction:
            return value == 0 ? "0" : LocktyDurationFormatter.abbreviated(value)
        case .unlocks, .notifications:
            return "\(Int(value))"
        }
    }

    // MARK: - Tooltip

    private func tooltip(for hour: Int) -> some View {
        VStack(spacing: 2) {
            Text(hourRangeText(hour))
                .font(.system(.footnote, design: .default, weight: .regular))
                .foregroundStyle(LocktyColors.secondaryText)

            Text(tooltipValue(hour))
                .font(.system(.headline, design: .default, weight: .semibold))
                .foregroundStyle(LocktyColors.primaryText)
                .monospacedDigit()
                .contentTransition(.numericText())

            // Only on the reduction tab, and only when the hour has a split worth
            // showing. Under a count of unlocks it would be answering a question nobody
            // asked.
            if metric == .reduction, state.hours[hour].classifiedTotal > 0 {
                HStack(spacing: LocktySpacing.sm) {
                    splitLabel(state.hours[hour].unproductive, color: LocktyColors.unproductive)
                    splitLabel(state.hours[hour].productive, color: LocktyColors.productive)
                }
                .padding(.top, 2)
            }
        }
        .padding(.horizontal, LocktySpacing.md)
        .padding(.vertical, LocktySpacing.sm)
        // Glass, like every other thing that floats over something else in the app. It
        // was a flat fill, which on top of a chart reads as a second card rather than as
        // a label held above one -- and the bars underneath should still be faintly
        // there, since the tooltip is about one of them.
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

    /// Keeps the tooltip on the card. Following the finger exactly walks it off both ends
    /// of the chart, where it is cut in half by the card's own edge.
    private func tooltipOffset(for hour: Int, columnWidth: CGFloat, width: CGFloat) -> CGFloat {
        let centre = columnWidth * (CGFloat(hour) + 0.5)
        let tooltipWidth: CGFloat = 128
        return min(max(centre - tooltipWidth / 2, 0), max(width - tooltipWidth, 0))
    }

    private func hourRangeText(_ hour: Int) -> String {
        String(format: "%d:00 - %d:00", hour, (hour + 1) % 24)
    }

    private func tooltipValue(_ hour: Int) -> String {
        let value = state.hours[hour]
        switch metric {
        case .reduction:
            return value.usage > 0 ? LocktyDurationFormatter.abbreviated(value.usage) : "0"
        case .unlocks:
            return "\(value.unlocks)"
        case .notifications:
            return "\(value.notifications)"
        }
    }
}
