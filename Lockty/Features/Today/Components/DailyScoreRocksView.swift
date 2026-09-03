import SwiftUI

/// Control, Detox and Productivity, as three pills whose rim is the score.
///
/// The rim is drawn, not blurred. An aura says roughly how it is going; a stroke that
/// stops at 71% of the way round says the number without repeating it, and the two
/// together -- a hard edge with its own glow behind it -- is the one place in the app
/// where a value is a shape rather than a colour.
///
/// No background and no pinning. They sit in the scroll like any other row.
struct DailyScoreRocksView: View {
    let metrics: [PrimaryMetric]
    var onSelect: ((PrimaryMetricKind) -> Void)?

    var body: some View {
        HStack(spacing: LocktySpacing.sm) {
            ForEach(metrics) { metric in
                pill(metric)
            }
        }
        .frame(maxWidth: .infinity)
    }

    private func pill(_ metric: PrimaryMetric) -> some View {
        Button {
            onSelect?(metric.kind)
        } label: {
            VStack(spacing: LocktySpacing.sm) {
                HStack(spacing: 6) {
                    Image(systemName: metric.kind.systemImage)
                        .font(.system(size: 15, weight: .medium))

                    Text("\(Int(metric.value.rounded()))")
                        .font(.system(size: 22, weight: .bold))
                        .monospacedDigit()
                        .contentTransition(.numericText())
                        .animation(.smooth(duration: 0.9), value: metric.value)
                }
                .foregroundStyle(LocktyColors.primaryText)
                .padding(.horizontal, LocktySpacing.md)
                .frame(height: 54)
                .frame(maxWidth: .infinity)
                .safeGlass(radius: 999, interactive: true)
                .overlay { rim(metric) }

                Text(metric.kind.title)
                    .font(.system(.footnote, design: .default, weight: .semibold))
                    .foregroundStyle(LocktyColors.secondaryText)
                    .lineLimit(1)
                    .minimumScaleFactor(0.8)
            }
        }
        .buttonStyle(.locktyInteractive(shape: Capsule(style: .continuous)))
        .tappable()
    }

    private func tint(_ metric: PrimaryMetric) -> Color {
        switch metric.tone {
        case .weak: LocktyColors.unproductive
        case .balanced: LocktyColors.warning
        case .strong: LocktyColors.productive
        }
    }

    /// The track, then the part of it that has been earned, then that same arc again
    /// blurred behind itself.
    ///
    /// The glow is a second copy rather than a shadow: a shadow follows the shape's
    /// whole outline, and what should be glowing is the arc, not the pill.
    private func rim(_ metric: PrimaryMetric) -> some View {
        let progress = max(min(metric.value / 100, 1), 0.02)

        return ZStack {
            Capsule(style: .continuous)
                .stroke(LocktyColors.ink(0.10), lineWidth: 2)

            Capsule(style: .continuous)
                .trim(from: 0, to: progress)
                .stroke(tint(metric), style: StrokeStyle(lineWidth: 2, lineCap: .round))
                .blur(radius: 5)
                .locktyGlow(lightScale: 0.7)

            Capsule(style: .continuous)
                .trim(from: 0, to: progress)
                .stroke(tint(metric), style: StrokeStyle(lineWidth: 2, lineCap: .round))
        }
        .animation(.smooth(duration: 0.9), value: metric.value)
    }
}
