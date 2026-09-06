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

    /// The card's own size, so its corner can be proportional to it.
    @State private var measuredSize: CGSize = .zero

    /// Proportional to the card, not a fixed number. `radius` is only the value used for
    /// the very first frame, before the size is known; after that every card is rounded
    /// to the same proportion as the full-width usage card, which is the only way the
    /// curvature reads the same on a tile and on a full-width card at once.
    ///
    /// Measuring cannot feed back into layout here: the radius only drives the fill, the
    /// clip and the border, never the frame.
    /// Two points more than asked for, on every edge.
    ///
    /// Left alone at zero: a card is passed 0 when its content lays itself out edge to
    /// edge -- a list whose rows carry their own insets, say -- and quietly adding a
    /// gutter there would break the alignment that was the point of asking for none.
    private var resolvedPadding: CGFloat {
        padding > 0 ? padding + 2 : 0
    }

    private var resolvedRadius: CGFloat {
        measuredSize == .zero ? radius : LocktyRadius.card(for: measuredSize)
    }

    var body: some View {
        let shape = RoundedRectangle(cornerRadius: resolvedRadius, style: .continuous)
        // Nil means "no colour of its own", not "white". White is the right default on
        // black -- the gradient is light being added -- and the wrong one on a pale page,
        // where white over white is nothing at all. The surface picks per scheme; this is
        // only what the press effect brightens with.
        let resolvedTint = tint ?? .white

        content
            .padding(resolvedPadding)
            .frame(
                maxWidth: expandsHorizontally ? .infinity : nil,
                minHeight: height,
                maxHeight: height,
                alignment: .leading
            )
            .onGeometryChange(for: CGSize.self) { $0.size } action: { newValue in
                measuredSize = newValue
            }
            .background {
                LocktyCardSurface(
                    shape: shape,
                    tint: tint,
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
    /// The card's own colour, or nil for one that has none.
    let tint: Color?
    let variant: LocktyCardBorderProfile

    @Environment(\.colorScheme) private var colorScheme

    private var isDark: Bool { colorScheme == .dark }

    /// What the fall of colour is drawn in.
    ///
    /// An untinted card gets white on black and ink on white, because the gradient is not
    /// a colour -- it is the card lifting off the page, and which direction that is depends
    /// on the page. It was white either way, so on a light screen every plain card was a
    /// white gradient over a white surface: the glow along the bottom edge that makes a
    /// card look like an object simply was not there.
    private var auraTint: Color {
        tint ?? (isDark ? .white : .black)
    }

    var body: some View {
        // The gradient is the card's entire fill. There is no flat base layer under it
        // any more: now that the gradient spans the whole card the two stacked on top of
        // each other, so the top of the card was being painted twice.
        //
        // In light mode the card is an opaque surface sitting *above* the page rather
        // than a wash of light over it: adding light to a light grey does almost nothing,
        // so a card built the dark way was invisible. The gradient survives, inverted --
        // the bottom edge is where the card lifts off the page, and it lifts by being
        // brighter in the dark and by casting a shadow in the light.
        // A ground first, then the tint over it. Both modes, in that order.
        //
        // The dark card used to be the gradient and nothing else, added to whatever was
        // behind it -- so it was not a surface at all, it was a wash. On the page that
        // passed; stacked (the insight cards sit three deep) each one showed the ones
        // underneath through itself and none of them could be read. An opaque ground is
        // what makes a card a card.
        //
        // And in light the white was standing in *for* the gradient rather than under
        // it, so every card was the same blank white however it was tinted -- the usage
        // card's green, a routine's colour, all painted out.
        shape
            .fill(isDark ? AnyShapeStyle(darkSurface) : AnyShapeStyle(lightSurface))
            .overlay {
                shape
                    .fill(isDark ? AnyShapeStyle(aura) : AnyShapeStyle(lightAura))
                    // Added on black, laid down on white: there is no light to add to
                    // white, and the same layer has to darken there instead.
                    .blendMode(isDark ? .plusLighter : .normal)
            }
            .overlay {
                shape
                    .strokeBorder(primaryBorder, lineWidth: variant.baseLineWidth)
            }
            .compositingGroup()
            .shadow(
                color: isDark ? .clear : Color.black.opacity(0.06),
                radius: 10,
                y: 4
            )
    }

    /// The dark-mode ground: near-black, and opaque.
    ///
    /// Not the page's own black -- a card the exact colour of what it sits on is not a
    /// card -- and not a translucent white either, which is what it was: over the page
    /// that reads as a faint lift, and over another card it reads as both of them at
    /// once. This is a colour, so a stack of them has a top one you can read.
    private var darkSurface: Color {
        Color(red: 0.075, green: 0.08, blue: 0.09)
    }

    /// The light-mode card: white, a touch cooler towards the bottom so it still has the
    /// same direction of light the dark one does.
    /// The same surface the smaller cards use, with the faintest fall towards the bottom
    /// so the card still has a top and a bottom. Not white: on a 0.945 page a paper-white
    /// card shouts, and the page is grey precisely so a card can be a little lighter
    /// rather than a lot.
    private var lightSurface: LinearGradient {
        LinearGradient(
            colors: [
                LocktyColors.cardSurface,
                LocktyColors.cardSurface.opacity(0.93)
            ],
            startPoint: .top,
            endPoint: .bottom
        )
    }

    /// The same fall of colour as the dark card's, at the strength a light ground needs.
    ///
    /// Drawn normally rather than added: there is no light to add to white. The values
    /// are roughly double the dark ones because `plusLighter` on black is a far stronger
    /// operator than laying a colour over white at the same opacity -- copying the dark
    /// numbers straight across left the card looking untinted, which is where this whole
    /// problem started.
    private var lightAura: LinearGradient {
        LinearGradient(
            stops: [
                .init(color: auraTint.opacity(0.04), location: 0.00),
                .init(color: auraTint.opacity(0.05), location: 0.38),
                .init(color: auraTint.opacity(0.07), location: 0.60),
                .init(color: auraTint.opacity(0.10), location: 0.75),
                .init(color: auraTint.opacity(0.16), location: 0.86),
                .init(color: auraTint.opacity(0.24), location: 0.94),
                .init(color: auraTint.opacity(0.32), location: 1.00)
            ],
            startPoint: .top,
            endPoint: .bottom
        )
    }

    /// Lit along the bottom edge, fading straight up to almost nothing.
    ///
    /// Vertical, with no sideways component at all. The axis used to be tilted
    /// down-and-right, which lit the bottom-right corner rather than the bottom edge and
    /// left every card looking as though the light came from somewhere off to one side.
    ///
    /// It spans the entire card. A fixed-height band anchored to the bottom drew a hard
    /// horizontal edge partway up wherever the card was taller than the band, which
    /// looked like the content had been cut across.
    private var aura: LinearGradient {
        LinearGradient(
            // Many closely spaced stops rather than a few: with four the ramp read as a
            // visible crease part-way down instead of a glow. The values are lower than
            // they look because they are added, not drawn over.
            stops: [
                .init(color: auraTint.opacity(0.020), location: 0.00),
                .init(color: auraTint.opacity(0.022), location: 0.38),
                .init(color: auraTint.opacity(0.030), location: 0.60),
                .init(color: auraTint.opacity(0.048), location: 0.75),
                .init(color: auraTint.opacity(0.080), location: 0.86),
                .init(color: auraTint.opacity(0.130), location: 0.94),
                .init(color: auraTint.opacity(0.190), location: 1.00)
            ],
            startPoint: .top,
            endPoint: .bottom
        )
    }

    /// The rim. White over a dark page, a dark hairline over a light one -- the same
    /// gradient either way, only in whichever colour is not the card's own.
    private var primaryBorder: LinearGradient {
        let edge = isDark ? auraTint : Color.black
        let scale = isDark ? 1.0 : 0.45

        return LinearGradient(
            stops: [
                .init(color: edge.opacity(variant.leadingOpacity * scale), location: 0),
                .init(color: edge.opacity(variant.upperMidOpacity * scale), location: 0.18),
                .init(color: edge.opacity(variant.lowerMidOpacity * scale), location: 0.62),
                .init(color: edge.opacity(variant.trailingOpacity * scale), location: 1)
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
