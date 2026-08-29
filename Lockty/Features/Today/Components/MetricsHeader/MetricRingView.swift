import SwiftUI

struct MetricRingView: View {
    let metric: PrimaryMetric
    let collapseProgress: CGFloat

    /// The label's natural (unconstrained) width, measured rather than hardcoded — forcing a
    /// fixed wrapper width made short labels like "DETOX" claim far more space than their text,
    /// which threw off the centering of the collapsed ring+label group.
    @State private var labelWidth: CGFloat = 0

    private var geometry: MetricsHeaderGeometry {
        MetricsHeaderGeometry(progress: collapseProgress)
    }

    private var color: Color {
        switch metric.tone {
        case .strong:
            LocktyColors.productive
        case .balanced:
            LocktyColors.neutral
        case .weak:
            LocktyColors.unproductive
        }
    }

    private var label: some View {
        Text(metric.kind.title.uppercased())
            .font(.caption2)
            .foregroundStyle(LocktyColors.secondaryText)
            .lineLimit(1)
            .fixedSize()
    }

    var body: some View {
        GeometryReader { proxy in
            let itemWidth = proxy.size.width
            let diameter = geometry.ringDiameter
            let collapsedGroupWidth = diameter + geometry.labelGap + labelWidth
            let collapsedGroupOriginX = max((itemWidth - collapsedGroupWidth) / 2, 0)
            let horizontalProgress = geometry.labelProgress
            // Dead centre at every stage. It used to slide left to make room for the
            // label beside it, but the label now fades out instead of moving next to the
            // ring, so there is nothing to make room for.
            let ringCenterX = itemWidth / 2
            let ringCenterY = geometry.contentTopOffset + (diameter / 2)
            let labelCenterX = MetricsHeaderGeometry.lerp(
                itemWidth / 2,
                collapsedGroupOriginX + diameter + geometry.labelGap + (labelWidth / 2),
                progress: horizontalProgress
            )
            let labelCenterY = geometry.contentTopOffset + MetricsHeaderGeometry.lerp(
                MetricsHeaderGeometry.expandedDiameter + geometry.labelGap + (MetricsHeaderGeometry.labelHeight / 2),
                diameter / 2,
                progress: horizontalProgress
            )

            ZStack(alignment: .topLeading) {
                ring(diameter: diameter)
                    .position(x: ringCenterX, y: ringCenterY)

                Text(metric.displayValue)
                    .font(.title2.weight(.bold))
                    .monospacedDigit()
                    .foregroundStyle(LocktyColors.primaryText)
                    .minimumScaleFactor(0.72)
                    .contentTransition(.numericText())
                    .frame(width: diameter, height: diameter, alignment: .center)
                    .position(x: ringCenterX, y: ringCenterY)

                label
                    .onGeometryChange(for: CGFloat.self) { $0.size.width } action: { newValue in
                        labelWidth = newValue
                    }
                    // Gone by the time the header is collapsed: what is left is the
                    // ring, smaller, with its number still in it.
                    .opacity(1 - horizontalProgress)
                    .position(x: labelCenterX, y: labelCenterY)
            }
            .frame(width: itemWidth, height: geometry.height, alignment: .topLeading)
        }
        .frame(height: geometry.height)
        .animation(.smooth(duration: 0.24), value: metric.displayValue)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(metric.kind.title)
        .accessibilityValue(metric.displayValue)
    }

    private func ring(diameter: CGFloat) -> some View {
        ZStack {
            Circle()
                .stroke(LocktyColors.elevatedBackground, lineWidth: geometry.strokeWidth)

            Circle()
                .trim(from: 0, to: metric.progress)
                .stroke(
                    color,
                    style: StrokeStyle(
                        lineWidth: geometry.strokeWidth,
                        lineCap: .round,
                        lineJoin: .round
                    )
                )
                .rotationEffect(.degrees(-90))
        }
        .frame(width: diameter, height: diameter)
    }
}
