import SwiftUI

/// A run of days as a line, with the ground under it filled.
///
/// The reusable one. Every trend in the app is the same picture -- a value per day, a
/// scale on the right, a few days named along the bottom -- and it was being redrawn from
/// scratch, differently, each time somebody needed one.
///
/// The line is dashed and the fill fades out downwards, which is not decoration: these
/// are daily totals from Screen Time, and a solid line drawn through them claims a
/// continuous measurement that does not exist. A dashed line reads as points joined up,
/// which is what it is.
struct LocktyTrendChart: View {
    struct Point: Identifiable, Equatable {
        let id: Int
        /// The value itself, in whatever unit the formatter below speaks.
        let value: Double
        /// The label under this point, if it gets one. Most do not -- a strip this wide
        /// cannot name fourteen days without the words touching.
        let label: String?
        /// What the tooltip calls it. Every point has one, because every point can be
        /// held: the axis labels are for orientation, this is for reading.
        let caption: String?

        init(id: Int, value: Double, label: String? = nil, caption: String? = nil) {
            self.id = id
            self.value = value
            self.label = label
            self.caption = caption
        }
    }

    let points: [Point]
    var tint: Color = LocktyColors.primaryText
    /// How to write a value on the scale. Given the value, returns the whole label.
    var format: (Double) -> String = { "\(Int($0))" }
    /// How many lines the scale is divided into, the top one included.
    var gridlines = 3
    var height: CGFloat = 190

    /// Which point a finger is resting on.
    @State private var focusedIndex: Int?

    /// The top of the scale. Rounded up so the highest point is not touching the ceiling,
    /// and never zero -- an empty chart still draws its scale rather than collapsing.
    private var maximum: Double {
        let peak = points.map(\.value).max() ?? 0
        guard peak > 0 else { return 1 }
        return peak * 1.15
    }

    var body: some View {
        HStack(alignment: .top, spacing: LocktySpacing.sm) {
            VStack(alignment: .leading, spacing: 0) {
                plot

                labels
                    .padding(.top, 6)
            }

            scale
        }
    }

    private var plot: some View {
        GeometryReader { proxy in
            ZStack(alignment: .topLeading) {
                gridlineLayer(in: proxy.size)

                if points.count >= 2 {
                    // The fill first, then the line over it: the line is the reading and
                    // must never be the thing that is faded.
                    area(in: proxy.size)
                        .fill(
                            LinearGradient(
                                colors: [tint.opacity(0.22), tint.opacity(0.02), .clear],
                                startPoint: .top,
                                endPoint: .bottom
                            )
                        )

                    line(in: proxy.size)
                        .stroke(
                            tint.opacity(0.85),
                            style: StrokeStyle(lineWidth: 2.5, lineCap: .round, lineJoin: .round, dash: [7, 6])
                        )

                    if let focusedIndex, points.indices.contains(focusedIndex) {
                        marker(at: focusedIndex, in: proxy.size)
                        tooltip(for: focusedIndex, in: proxy.size)
                    }
                }
            }
            .contentShape(Rectangle())
            // The whole plot is the control: a line has no targets to hit, so the
            // nearest point to the finger is the one being asked about.
            .gesture(
                DragGesture(minimumDistance: 0)
                    .onChanged { value in
                        let step = points.count > 1 ? proxy.size.width / CGFloat(points.count - 1) : 0
                        guard step > 0 else { return }
                        let index = Int((value.location.x / step).rounded())
                        focusedIndex = min(max(index, 0), points.count - 1)
                    }
                    .onEnded { _ in
                        withAnimation(.smooth(duration: 0.2)) { focusedIndex = nil }
                    }
            )
            .sensoryFeedback(.selection, trigger: focusedIndex)
        }
        .frame(height: height)
    }

    /// The line down to the point being read, and the point itself.
    private func marker(at index: Int, in size: CGSize) -> some View {
        let point = position(index, in: size)

        return ZStack(alignment: .topLeading) {
            Rectangle()
                .fill(tint.opacity(0.35))
                .frame(width: 1, height: max(size.height - point.y, 0))
                .offset(x: point.x, y: point.y)

            Circle()
                .fill(tint)
                .frame(width: 9, height: 9)
                .offset(x: point.x - 4.5, y: point.y - 4.5)
        }
        .allowsHitTesting(false)
    }

    /// What that day was, held above the point.
    private func tooltip(for index: Int, in size: CGSize) -> some View {
        let point = position(index, in: size)
        let width: CGFloat = 120

        return VStack(spacing: 2) {
            if let caption = points[index].caption {
                Text(caption)
                    .font(.system(.caption2, design: .default, weight: .regular))
                    .foregroundStyle(LocktyColors.secondaryText)
            }

            Text(format(points[index].value))
                .font(.system(.subheadline, design: .default, weight: .semibold))
                .foregroundStyle(LocktyColors.primaryText)
                .monospacedDigit()
                .contentTransition(.numericText())
        }
        .padding(.horizontal, LocktySpacing.md)
        .padding(.vertical, 6)
        .safeGlass(radius: 14)
        .locktyImperfectBorder(RoundedRectangle(cornerRadius: 14, style: .continuous))
        .fixedSize()
        // Kept on the chart: following the finger exactly walks it off both ends, where
        // it is cut in half by the edge of the screen.
        .offset(
            x: min(max(point.x - width / 2, 0), max(size.width - width, 0)),
            y: max(point.y - 46, -8)
        )
        .allowsHitTesting(false)
        .transition(.blurReplace)
    }

    /// Where a point sits inside the plot.
    private func position(_ index: Int, in size: CGSize) -> CGPoint {
        let step = points.count > 1 ? size.width / CGFloat(points.count - 1) : 0
        let ratio = maximum > 0 ? points[index].value / maximum : 0
        return CGPoint(x: step * CGFloat(index), y: size.height * (1 - CGFloat(ratio)))
    }

    /// The line itself, rounded through its points.
    ///
    /// A Catmull-Rom style smoothing done with the midpoints: it curves without
    /// overshooting, which matters when the values cannot go below zero and a naive
    /// spline would dip a quiet day under the floor.
    private func line(in size: CGSize) -> Path {
        var path = Path()
        guard points.count >= 2 else { return path }

        path.move(to: position(0, in: size))
        for index in 1..<points.count {
            let previous = position(index - 1, in: size)
            let current = position(index, in: size)
            let midpoint = CGPoint(x: (previous.x + current.x) / 2, y: (previous.y + current.y) / 2)
            path.addQuadCurve(to: midpoint, control: previous)
            path.addQuadCurve(to: current, control: midpoint)
        }
        return path
    }

    private func area(in size: CGSize) -> Path {
        var path = line(in: size)
        guard points.count >= 2 else { return path }

        path.addLine(to: CGPoint(x: size.width, y: size.height))
        path.addLine(to: CGPoint(x: 0, y: size.height))
        path.closeSubpath()
        return path
    }

    private func gridlineLayer(in size: CGSize) -> some View {
        VStack(spacing: 0) {
            ForEach(0..<max(gridlines, 1), id: \.self) { index in
                Rectangle()
                    .fill(LocktyColors.separator.opacity(0.28))
                    .frame(height: 1)

                if index < gridlines - 1 { Spacer(minLength: 0) }
            }
        }
        .frame(height: size.height)
        .allowsHitTesting(false)
    }

    /// The values up the right-hand edge, top first.
    private var scale: some View {
        VStack(alignment: .trailing, spacing: 0) {
            ForEach(0..<max(gridlines, 1), id: \.self) { index in
                Text(format(maximum * (1 - Double(index) / Double(max(gridlines - 1, 1)))))
                    .font(.system(.caption2, design: .default, weight: .regular))
                    .foregroundStyle(LocktyColors.tertiaryText)
                    .monospacedDigit()
                    .offset(y: -6)

                if index < gridlines - 1 { Spacer(minLength: 0) }
            }
        }
        .frame(height: height, alignment: .top)
        .fixedSize(horizontal: true, vertical: false)
    }

    /// The named days along the bottom, each sitting under its own point.
    private var labels: some View {
        GeometryReader { proxy in
            let step = points.count > 1 ? proxy.size.width / CGFloat(points.count - 1) : 0

            ForEach(points) { point in
                if let label = point.label {
                    Text(label)
                        .font(.system(.caption2, design: .default, weight: .regular))
                        .foregroundStyle(LocktyColors.tertiaryText)
                        .fixedSize()
                        .offset(x: step * CGFloat(point.id) - 8)
                }
            }
        }
        .frame(height: 14)
    }
}
