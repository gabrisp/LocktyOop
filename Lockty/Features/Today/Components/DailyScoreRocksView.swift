import SwiftUI

/// Control, Detox and Productivity, as three small versions of the badge above them.
///
/// The same rock, not a second visual language: they are the same kind of thing as the
/// score at the top of the screen -- a number out of a hundred about how the day went --
/// and drawing them as rings or pills would say they were something else. Smaller, side
/// by side, and each lit by its own value.
///
/// No background and no pinning. They sit in the scroll like any other row: the badge
/// above is the one thing on this screen worth keeping in view, and three of them
/// competing for the top would leave nothing but headings there.
struct DailyScoreRocksView: View {
    let metrics: [PrimaryMetric]
    var onSelect: ((PrimaryMetricKind) -> Void)?

    @Environment(\.colorScheme) private var colorScheme

    private let side: CGFloat = 104

    var body: some View {
        HStack(spacing: LocktySpacing.sm) {
            ForEach(metrics) { metric in
                rock(metric)
            }
        }
        .frame(maxWidth: .infinity)
    }

    private func rock(_ metric: PrimaryMetric) -> some View {
        Button {
            onSelect?(metric.kind)
        } label: {
            VStack(spacing: 2) {
                ZStack {
                    bloom(metric)
                    body(metric)
                    value(metric)
                }
                .frame(width: side, height: side * 0.78)
                .compositingGroup()

                Text(metric.kind.title)
                    .font(.system(.footnote, design: .default, weight: .semibold))
                    .foregroundStyle(
                        colorScheme == .dark
                        ? LocktyColors.secondaryText
                        : LocktyColors.deep(tint(metric))
                    )
                    .lineLimit(1)
                    .minimumScaleFactor(0.8)
            }
            .frame(maxWidth: .infinity)
        }
        .buttonStyle(.locktyInteractive(brighten: true))
        .tappable()
    }

    private func tint(_ metric: PrimaryMetric) -> Color {
        switch metric.tone {
        case .weak: LocktyColors.unproductive
        case .balanced: LocktyColors.warning
        case .strong: LocktyColors.productive
        }
    }

    /// The same blurred silhouette the big badge uses, so the light follows the shape
    /// rather than being a circle behind an irregular thing.
    private func bloom(_ metric: PrimaryMetric) -> some View {
        RockShape()
            .fill(tint(metric))
            .frame(width: side * 0.86, height: side * 0.86)
            .blur(radius: 20)
            .opacity(0.75)
            .locktyGlow(lightScale: 0.6)
            .animation(.smooth(duration: 0.6), value: metric.value)
    }

    private func body(_ metric: PrimaryMetric) -> some View {
        let shape = RockShape()

        return shape
            .fill(tint(metric).opacity(0.16))
            .background { shape.fill(LocktyColors.background) }
            .overlay {
                // The rim inward, in the screen's own ground: a wide stroke blurred and
                // clipped inside the shape, which is what turns a flat silhouette into
                // something with a body.
                shape
                    .stroke(LocktyColors.background, lineWidth: 12)
                    .blur(radius: 7)
                    .mask { shape }
            }
            .frame(width: side * 0.74, height: side * 0.74)
            .animation(.smooth(duration: 0.6), value: metric.value)
    }

    /// White type with the colour behind it rather than in it, as on the big one: the
    /// number stays legible at any score and reads as lit by what it sits on.
    private func value(_ metric: PrimaryMetric) -> some View {
        let text = Text("\(Int(metric.value.rounded()))")
            .font(.system(size: 26, weight: .heavy))
            .monospacedDigit()
            .contentTransition(.numericText())

        return text
            .foregroundStyle(colorScheme == .dark ? .white : LocktyColors.deep(tint(metric)))
            .background {
                text
                    .foregroundStyle(tint(metric))
                    .blur(radius: 7)
                    .locktyGlow(lightScale: 0.85)
                    .opacity(colorScheme == .dark ? 1 : 0)
            }
            .animation(.smooth(duration: 0.9), value: metric.value)
    }
}
