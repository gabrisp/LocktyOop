import SwiftUI

/// The one picker used everywhere in a flow: a scroll view whose centred row is the
/// selection, held in a glass capsule, with every other row tilting, blurring and fading
/// away from it.
///
/// Not a stack of buttons -- selecting is scrolling. The row that lands in the middle is
/// the answer, which is why the same component can present minutes and apps without
/// either looking like a different control.
struct LocktyWheelPicker<Item: Hashable, Row: View>: View {
    let items: [Item]
    @Binding var selection: Item?
    var rowHeight: CGFloat = 58
    @ViewBuilder let row: (Item) -> Row

    /// The picker's own height. It takes everything it is given rather than a fixed
    /// number of rows, and the content margins are derived from it so the pill stays
    /// exactly in the middle whatever that height turns out to be.
    @State private var measuredHeight: CGFloat = 0

    private var verticalMargin: CGFloat {
        max(0, (measuredHeight - rowHeight) / 2)
    }

    var body: some View {
        ScrollView(.vertical, showsIndicators: false) {
            LazyVStack(spacing: 0) {
                ForEach(items, id: \.self) { item in
                    row(item)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .frame(height: rowHeight)
                        // phase.value runs about -1 to 1 across the viewport, so it can
                        // drive the tilt directly: rows lean away from the middle around
                        // the x axis, and blur and fade as they go, which is what makes a
                        // flat scroll view read as a wheel turning.
                        .scrollTransition(.interactive, axis: .vertical) { content, phase in
                            content
                                .opacity(1 - abs(phase.value) * 0.8)
                                .blur(radius: abs(phase.value) * 3.5)
                                .scaleEffect(1 - abs(phase.value) * 0.14)
                                .rotation3DEffect(
                                    .degrees(phase.value * 38),
                                    axis: (x: 1, y: 0, z: 0),
                                    perspective: 0.45
                                )
                        }
                        .id(item)
                }
            }
            .scrollTargetLayout()
        }
        // Half the empty space either end, so the first and last rows can reach the pill
        // instead of stopping at the edge of the viewport.
        .contentMargins(.vertical, verticalMargin, for: .scrollContent)
        .scrollIndicators(.hidden)
        .scrollTargetBehavior(.viewAligned)
        .scrollPosition(id: $selection, anchor: .center)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .onGeometryChange(for: CGFloat.self) { $0.size.height } action: { newValue in
            measuredHeight = newValue
        }
        // The pill is fixed in the middle and the rows travel under it -- it is the
        // selector, not a decoration on the selected row. Behind the content so the row
        // reads on top of it, and never in the way of the scroll.
        .background {
            Capsule(style: .continuous)
                .fill(.ultraThinMaterial)
                .frame(height: rowHeight)
                .allowsHitTesting(false)
        }
        // Fades out at both ends so rows arrive and leave rather than being cut off at
        // the viewport edge. Outside the pill's background, or the pill would fade with
        // them.
        .mask {
            LinearGradient(
                stops: [
                    .init(color: .black.opacity(0), location: 0),
                    .init(color: .black, location: 0.28),
                    .init(color: .black, location: 0.72),
                    .init(color: .black.opacity(0), location: 1)
                ],
                startPoint: .top,
                endPoint: .bottom
            )
        }
        .sensoryFeedback(.selection, trigger: selection)
        .animation(.smooth(duration: 0.2), value: selection)
    }
}
