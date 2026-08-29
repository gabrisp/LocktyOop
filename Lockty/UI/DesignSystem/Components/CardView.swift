import SwiftUI

struct CardView<Content: View>: View {
    let radius: CGFloat
    let padding: CGFloat
    let interactive: Bool
    let height: CGFloat?
    let expandsHorizontally: Bool
    let tint: Color?
    let content: Content
    @State private var borderVariantIndex: Int

    init(
        radius: CGFloat = LocktyRadius.medium,
        padding: CGFloat = LocktySpacing.md,
        interactive: Bool = false,
        height: CGFloat? = nil,
        expandsHorizontally: Bool = true,
        tint: Color? = nil,
        styleVariant: Int? = nil,
        @ViewBuilder content: () -> Content
    ) {
        self.radius = radius
        self.padding = padding
        self.interactive = interactive
        self.height = height
        self.expandsHorizontally = expandsHorizontally
        self.tint = tint
        self.content = content()
        _borderVariantIndex = State(initialValue: styleVariant ?? LocktyCardBorderVariantAllocator.next())
    }

    var body: some View {
        let shape = RoundedRectangle(cornerRadius: radius, style: .continuous)
        let resolvedTint = tint ?? .white

        content
            .padding(padding)
            .frame(
                maxWidth: expandsHorizontally ? .infinity : nil,
                minHeight: height,
                maxHeight: height,
                alignment: .leading
            )
            .background {
                LocktyCardSurface(
                    shape: shape,
                    tint: resolvedTint,
                    variant: LocktyCardBorderProfile(index: borderVariantIndex)
                )
            }
            .clipShape(shape)
            // A card is a widget, not a button: pressing it grows it, the way a
            // long-pressed widget does. Buttons keep the default shrink.
            .locktyInteractiveSurface(
                enabled: interactive,
                tint: resolvedTint,
                shape: shape,
                pressedScale: 1.02
            )
    }
}

private struct LocktyCardSurface<S: InsettableShape>: View {
    let shape: S
    let tint: Color
    let variant: LocktyCardBorderProfile

    var body: some View {
        // The gradient is the card's entire fill. There is no flat base layer under it
        // any more: now that the gradient spans the whole card the two stacked on top of
        // each other, so the top of the card was being painted twice.
        shape
            .fill(aura)
            .overlay {
                shape
                    .strokeBorder(primaryBorder, lineWidth: variant.baseLineWidth)
            }
            .compositingGroup()
    }

    /// Bright at the bottom edge and almost flat above it: 0.30 on the last line of the
    /// card falling away to 0.05, so the glow reads as coming from under the card rather
    /// than washing up its whole face, while the flat part is what gives the card its
    /// surface.
    ///
    /// It spans the entire card. A fixed-height band anchored to the bottom drew a hard
    /// horizontal edge partway up wherever the card was taller than the band, which
    /// looked like the content had been cut across.
    private var aura: LinearGradient {
        LinearGradient(
            // Many closely spaced stops rather than a few: with four the ramp read as a
            // visible crease part-way down instead of a glow.
            stops: [
                .init(color: tint.opacity(0.050), location: 0.00),
                .init(color: tint.opacity(0.055), location: 0.30),
                .init(color: tint.opacity(0.070), location: 0.52),
                .init(color: tint.opacity(0.100), location: 0.70),
                .init(color: tint.opacity(0.140), location: 0.83),
                .init(color: tint.opacity(0.200), location: 0.92),
                .init(color: tint.opacity(0.260), location: 0.97),
                .init(color: tint.opacity(0.300), location: 1.00)
            ],
            // Tilted down-and-right so points on the right sit further along the axis:
            // the bright end rides higher on that side instead of being level.
            startPoint: UnitPoint(x: 0.32, y: 0),
            endPoint: UnitPoint(x: 0.68, y: 1)
        )
    }

    private var primaryBorder: LinearGradient {
        LinearGradient(
            stops: [
                .init(color: tint.opacity(variant.leadingOpacity), location: 0),
                .init(color: tint.opacity(variant.upperMidOpacity), location: 0.18),
                .init(color: tint.opacity(variant.lowerMidOpacity), location: 0.62),
                .init(color: tint.opacity(variant.trailingOpacity), location: 1)
            ],
            startPoint: .topLeading,
            endPoint: .bottomTrailing
        )
    }
}

private struct LocktyCardBorderProfile {
    let baseLineWidth: CGFloat
    let leadingOpacity: Double
    let upperMidOpacity: Double
    let lowerMidOpacity: Double
    let trailingOpacity: Double

    init(index: Int) {
        switch index % 5 {
        case 0:
            baseLineWidth = 0.92
            leadingOpacity = 0.20
            upperMidOpacity = 0.14
            lowerMidOpacity = 0.08
            trailingOpacity = 0.05
        case 1:
            baseLineWidth = 1.04
            leadingOpacity = 0.16
            upperMidOpacity = 0.12
            lowerMidOpacity = 0.09
            trailingOpacity = 0.06
        case 2:
            baseLineWidth = 0.88
            leadingOpacity = 0.18
            upperMidOpacity = 0.11
            lowerMidOpacity = 0.07
            trailingOpacity = 0.04
        case 3:
            baseLineWidth = 1.08
            leadingOpacity = 0.22
            upperMidOpacity = 0.15
            lowerMidOpacity = 0.10
            trailingOpacity = 0.05
        default:
            baseLineWidth = 0.96
            leadingOpacity = 0.17
            upperMidOpacity = 0.13
            lowerMidOpacity = 0.09
            trailingOpacity = 0.05
        }
    }
}

@MainActor
private enum LocktyCardBorderVariantAllocator {
    private static var current = 0

    static func next() -> Int {
        let value = current
        current = (current + 1) % 5
        return value
    }
}
