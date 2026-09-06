import SwiftUI

/// What a score is made of, as a row of rings.
///
/// These were bars, and bars were the wrong picture. A bar is a *quantity* -- it says how
/// much of something there is -- and none of these are quantities: they are weights, the
/// share each part carries in the number above them. A ring is a share by construction:
/// it is full or it is not, and three of them side by side are read against each other in
/// one glance rather than measured against a left edge.
///
/// They draw themselves in when the section arrives, one after another, because the
/// filling *is* the reading -- a ring already full when you get to it is a circle.
struct LocktyWeightRings: View {
    struct Item: Identifiable, Equatable {
        let id: String
        let title: String
        /// Out of a hundred.
        let weight: Int
        /// The colour of this part. Nil takes the row's own tint.
        let tint: Color?

        init(id: String? = nil, title: String, weight: Int, tint: Color? = nil) {
            self.id = id ?? title
            self.title = title
            self.weight = weight
            self.tint = tint
        }
    }

    let items: [Item]
    var tint: Color = LocktyColors.primaryText

    /// Whether the rings have filled yet. They start empty and are asked to fill on
    /// arrival, which is the whole animation.
    @State private var hasFilled = false

    @Environment(\.colorScheme) private var colorScheme

    private let side: CGFloat = 74
    private let lineWidth: CGFloat = 6

    var body: some View {
        HStack(alignment: .top, spacing: LocktySpacing.md) {
            ForEach(Array(items.enumerated()), id: \.element.id) { index, item in
                VStack(spacing: LocktySpacing.sm) {
                    ring(item, index: index)

                    Text(item.title)
                        .font(.system(.caption, design: .default, weight: .regular))
                        .foregroundStyle(LocktyColors.secondaryText)
                        .multilineTextAlignment(.center)
                        .lineLimit(2)
                        .fixedSize(horizontal: false, vertical: true)
                }
                .frame(maxWidth: .infinity)
            }
        }
        .task {
            // A beat after the section lands, so the fill is something you watch happen
            // rather than something that has already happened.
            try? await Task.sleep(for: .milliseconds(120))
            hasFilled = true
        }
    }

    private func ring(_ item: Item, index: Int) -> some View {
        let colour = item.tint ?? tint
        let progress = hasFilled ? Double(item.weight) / 100 : 0
        let isDark = colorScheme == .dark

        return ZStack {
            Circle()
                .stroke(LocktyColors.ink(0.10), lineWidth: lineWidth)

            // The light coming off the filled part. A second copy of the arc rather than
            // a shadow: a shadow follows the whole circle, and what should be glowing is
            // the part that is filled.
            Circle()
                .trim(from: 0, to: progress)
                .stroke(colour, style: StrokeStyle(lineWidth: lineWidth, lineCap: .round))
                .blur(radius: 5)
                .opacity(isDark ? 1 : 0.5)
                .blendMode(isDark ? .plusLighter : .normal)

            Circle()
                .trim(from: 0, to: progress)
                .stroke(colour, style: StrokeStyle(lineWidth: lineWidth, lineCap: .round))
        }
        // From the top, clockwise. A circle's path starts at three o'clock, which puts
        // the beginning of every one of these on its right-hand edge -- fine for a ring
        // that is always full, wrong for one whose start is the thing being read.
        .rotationEffect(.degrees(-90))
        .frame(width: side, height: side)
        // Staggered, left to right, so the three read as a sequence rather than as one
        // thing happening in three places.
        .animation(.smooth(duration: 0.75).delay(Double(index) * 0.1), value: hasFilled)
        // The figure sits outside the rotation: turned with the arcs it would be lying
        // on its side.
        .overlay {
            Text("\(item.weight)%")
                .font(.system(.footnote, design: .default, weight: .semibold))
                .foregroundStyle(LocktyColors.primaryText)
                .monospacedDigit()
                .contentTransition(.numericText())
        }
    }
}
