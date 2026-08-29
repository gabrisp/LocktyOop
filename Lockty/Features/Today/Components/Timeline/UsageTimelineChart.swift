import SwiftUI

struct UsageTimelineChart: View {
    let state: UsageTimelineChartState

    private var maxMinutes: Double {
        let maximum = state.buckets.map {
            max($0.aboveBaseline, $0.unproductive) / 60
        }
        .max() ?? 1

        return max(maximum, 1)
    }

    var body: some View {
        VStack(spacing: LocktySpacing.sm) {
            GeometryReader { proxy in
                ZStack(alignment: .topLeading) {
                    ForEach(state.overlays) { overlay in
                        TimelineOverlayBand(
                            overlay: overlay,
                            chartWidth: proxy.size.width,
                            chartHeight: proxy.size.height
                        )
                    }

                    // Explicitly filling the reader's size: each bar's two halves are
                    // maxHeight: .infinity, so without this the row collapsed to its
                    // intrinsic height on any day with no overlay bands to stretch the
                    // ZStack, leaving the bars adrift from the baseline underneath.
                    HStack(alignment: .center, spacing: 3) {
                        ForEach(state.buckets) { bucket in
                            TimelineBucketBar(
                                bucket: bucket,
                                maxMinutes: maxMinutes,
                                maxBarHeight: proxy.size.height * 0.38
                            )
                        }
                    }
                    .frame(width: proxy.size.width, height: proxy.size.height)

                    Rectangle()
                        .fill(LocktyColors.cardStroke)
                        .frame(height: 1)
                        .offset(y: proxy.size.height / 2)
                }
            }

            HStack {
                Text("00")
                Spacer()
                Text("06")
                Spacer()
                Text("12")
                Spacer()
                Text("18")
                Spacer()
                Text("24")
            }
            .font(.caption2.weight(.medium))
            .monospacedDigit()
            .foregroundStyle(LocktyColors.tertiaryText)
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Digital balance timeline")
    }
}

private struct TimelineBucketBar: View {
    let bucket: UsageTimelineBucket
    let maxMinutes: Double
    let maxBarHeight: CGFloat

    private var productiveHeight: CGFloat {
        height(for: bucket.productive)
    }

    private var neutralHeight: CGFloat {
        height(for: bucket.neutral)
    }

    private var unproductiveHeight: CGFloat {
        height(for: bucket.unproductive)
    }

    var body: some View {
        VStack(spacing: 0) {
            VStack(spacing: 2) {
                Spacer(minLength: 0)

                RoundedRectangle(cornerRadius: 2, style: .continuous)
                    .fill(LocktyColors.productive)
                    .frame(height: productiveHeight)

                RoundedRectangle(cornerRadius: 2, style: .continuous)
                    .fill(LocktyColors.neutral.opacity(0.72))
                    .frame(height: neutralHeight)
            }
            .frame(maxHeight: .infinity)

            Color.clear.frame(height: 1)

            VStack(spacing: 2) {
                RoundedRectangle(cornerRadius: 2, style: .continuous)
                    .fill(LocktyColors.unproductive)
                    .frame(height: unproductiveHeight)

                Spacer(minLength: 0)
            }
            .frame(maxHeight: .infinity)
        }
        .frame(maxWidth: .infinity)
    }

    private func height(for duration: TimeInterval) -> CGFloat {
        let minutes = duration / 60
        guard minutes > 0 else { return 0 }
        return CGFloat(max((minutes / maxMinutes) * maxBarHeight, 2))
    }
}

private struct TimelineOverlayBand: View {
    let overlay: UsageTimelineOverlay
    let chartWidth: CGFloat
    let chartHeight: CGFloat

    var body: some View {
        RoundedRectangle(cornerRadius: 5, style: .continuous)
            .fill(color.opacity(0.12))
            .frame(width: width, height: chartHeight)
            .offset(x: xOffset)
    }

    private var color: Color {
        switch overlay.type {
        case .routine, .focus:
            LocktyColors.productive
        case .detox:
            LocktyColors.neutral
        case .breakPeriod, .freeTime:
            LocktyColors.warning
        case .distraction:
            LocktyColors.unproductive
        }
    }

    private var xOffset: CGFloat {
        ratio(for: overlay.startDate) * chartWidth
    }

    private var width: CGFloat {
        max((ratio(for: overlay.endDate) - ratio(for: overlay.startDate)) * chartWidth, 3)
    }

    private func ratio(for date: Date) -> CGFloat {
        let calendar = Calendar.current
        let components = calendar.dateComponents([.hour, .minute], from: date)
        let minutes = Double((components.hour ?? 0) * 60 + (components.minute ?? 0))
        return CGFloat(min(max(minutes / (24 * 60), 0), 1))
    }
}
