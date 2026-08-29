import SwiftUI

/// The one picker used everywhere in a flow: a scroll view whose centred row is the
/// selection, held in a glass capsule, with the rest fading and shrinking away from it.
///
/// Not a stack of buttons -- selecting is scrolling. The row that lands in the middle is
/// the answer, which is why the same component can present minutes and apps without
/// either looking like a different control.
struct LocktyWheelPicker<Item: Hashable, Row: View>: View {
    let items: [Item]
    @Binding var selection: Item?
    var rowHeight: CGFloat = 58
    var visibleRows: Int = 7
    @ViewBuilder let row: (Item) -> Row

    var body: some View {
        ScrollView(.vertical, showsIndicators: false) {
            LazyVStack(spacing: 0) {
                ForEach(items, id: \.self) { item in
                    row(item)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .frame(height: rowHeight)
                        // Distance from the middle is what makes a plain scroll view
                        // read as a wheel.
                        .scrollTransition(.interactive, axis: .vertical) { content, phase in
                            content
                                .opacity(phase.isIdentity ? 1 : 0.25)
                                .scaleEffect(phase.isIdentity ? 1 : 0.92)
                        }
                        .id(item)
                }
            }
            .scrollTargetLayout()
        }
        // Half the empty space either end, so the first and last rows can sit under the
        // pill instead of stopping at the edge of the viewport.
        .contentMargins(.vertical, rowHeight * CGFloat(visibleRows - 1) / 2, for: .scrollContent)
        .scrollIndicators(.hidden)
        .scrollTargetBehavior(.viewAligned)
        .scrollPosition(id: $selection, anchor: .center)
        // Room for exactly the rows either side, so the capsule sits in the middle.
        .frame(height: rowHeight * CGFloat(visibleRows))
        // The pill is fixed in the middle and the rows travel under it -- it is the
        // selector, not a decoration on the selected row. Drawn behind the content so
        // the row reads on top of it, and never in the way of the scroll.
        .background {
            Capsule(style: .continuous)
                .fill(.ultraThinMaterial)
                .frame(height: rowHeight)
                .allowsHitTesting(false)
        }
        // Fades out at both ends so rows arrive and leave rather than being cut off at
        // the edge of the viewport. Applied outside the pill's background, or the pill
        // would fade with them.
        .mask {
            LinearGradient(
                stops: [
                    .init(color: .black.opacity(0), location: 0),
                    .init(color: .black, location: 0.22),
                    .init(color: .black, location: 0.78),
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
