import SwiftUI

struct MetricRingView: View {
    let metric: PrimaryMetric
    let collapseProgress: CGFloat

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

    var body: some View {
        GeometryReader { proxy in
            let itemWidth = proxy.size.width
            let diameter = geometry.ringDiameter
            let labelWidth = MetricsHeaderGeometry.lerp(
                MetricsHeaderGeometry.expandedLabelWidth,
                MetricsHeaderGeometry.collapsedLabelWidth,
                progress: geometry.labelProgress
            )
            let collapsedGroupWidth = diameter + geometry.labelGap + labelWidth
            let collapsedGroupOriginX = (itemWidth - collapsedGroupWidth) / 2
            let ringCenterX = MetricsHeaderGeometry.lerp(
                itemWidth / 2,
                collapsedGroupOriginX + (diameter / 2),
                progress: collapseProgress
            )
            let ringCenterY = geometry.contentTopOffset + (diameter / 2)
            let labelCenterX = MetricsHeaderGeometry.lerp(
                itemWidth / 2,
                collapsedGroupOriginX + diameter + geometry.labelGap + (labelWidth / 2),
                progress: geometry.labelProgress
            )
            let labelCenterY = geometry.contentTopOffset + MetricsHeaderGeometry.lerp(
                MetricsHeaderGeometry.expandedDiameter + geometry.labelGap + (MetricsHeaderGeometry.labelHeight / 2),
                diameter / 2,
                progress: geometry.labelProgress
            )
            let labelTextShift = MetricsHeaderGeometry.lerp(
                0,
                -(max(labelWidth - metric.kind.collapsedTextWidth, 0) / 2),
                progress: geometry.labelTextShiftProgress
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
                    .opacity(geometry.valueOpacity)
                    .position(x: ringCenterX, y: ringCenterY)

                Text(metric.kind.title.uppercased())
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(LocktyColors.secondaryText)
                    .lineLimit(1)
                    .frame(
                        width: labelWidth,
                        height: MetricsHeaderGeometry.labelHeight,
                        alignment: .center
                    )
                    .multilineTextAlignment(.center)
                    .offset(x: labelTextShift)
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
