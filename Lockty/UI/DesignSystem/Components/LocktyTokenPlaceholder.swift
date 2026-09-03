import FamilyControls
import ManagedSettings
import SwiftUI

/// Anything that has to sit in a row of app icons and be exactly the size of one: the
/// "+N" tile at the end of a stack, an empty slot in a folder, a tinted stand-in.
///
/// FamilyControls draws `Label(token)` at its own size and ignores whatever frame it is
/// handed, so a placeholder built from a `RoundedRectangle` at some chosen number is the
/// same size as the icons beside it only by coincidence -- and stops being so the moment
/// anything scales them.
///
/// Masking a fill with the token does not work: the system renders that label out of
/// process, and a layer SwiftUI does not draw itself cannot act as a mask -- the result
/// is nothing at all. So the token is *measured* instead. A hidden copy is laid out
/// purely to report the size the system gave it, and the placeholder is drawn at exactly
/// that size. Being a real layout, every modifier applied around this -- scaleEffect,
/// frames, clips -- lands on it identically to the way it lands on the icons.
///
/// This is the same trick `LocktyAppLockBadge` uses to size its ring.
struct LocktyTokenPlaceholder: View {
    /// Any app icon. Only its size is used, never its picture.
    let stencil: ApplicationToken?
    /// What the placeholder is filled with. A flat colour, a tint at low opacity, a
    /// routine's accent -- whatever the row it belongs to calls for.
    var fill: Color = LocktyColors.elevatedBackground
    /// Used only until the measurement lands, and when there is no token to measure.
    var fallbackSide: CGFloat = 38

    /// The size the system drew the stencil at. Zero until the first layout pass.
    @State private var measured: CGSize = .zero

    private var side: CGSize {
        measured.width > 0 && measured.height > 0
            ? measured
            : CGSize(width: fallbackSide, height: fallbackSide)
    }

    /// The proportion iOS rounds an app icon by, so the tile reads as one of them rather
    /// than as a rounded rectangle that happens to be the same size.
    private var cornerRadius: CGFloat {
        min(side.width, side.height) * 0.2237
    }

    var body: some View {
        RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
            .fill(fill)
            .frame(width: side.width, height: side.height)
            .background {
                // Laid out, never drawn. `hidden()` keeps the view in the layout -- which
                // is the whole point, since its size is the answer -- while drawing
                // nothing, so the real icon never shows through the tile in front of it.
                if let stencil {
                    Label(stencil)
                        .labelStyle(.iconOnly)
                        .id(stencil)
                        .hidden()
                        .onGeometryChange(for: CGSize.self) { proxy in
                            proxy.size
                        } action: { newValue in
                            measured = newValue
                        }
                }
            }
    }
}

/// Up to three app icons overlapping, with the count of whatever didn't fit carried on a
/// tile at the end rather than as separate text.
///
/// One component rather than the copy that sat in the routine card and the rule card:
/// they were the same view written twice, and the overflow tile had drifted in both --
/// it was laid out a whole overlap wider than the icons, so it read as a longer tile
/// rather than as one more of them.
struct LocktyStackedAppTokens: View {
    let tokens: [ApplicationToken]
    var iconSize: CGFloat = 22
    var overlap: CGFloat = 7

    private var visible: [ApplicationToken] {
        Array(tokens.prefix(3))
    }

    private var overflow: Int {
        max(0, tokens.count - visible.count)
    }

    var body: some View {
        HStack(spacing: -overlap) {
            ForEach(Array(visible.enumerated()), id: \.element) { index, token in
                slot {
                    Label(token)
                        .labelStyle(.iconOnly)
                        .id(token)
                }
                // The count goes *on* the last icon rather than after it. A tile of its
                // own read as one more app, and it cost a slot that could have shown a
                // real one. Darkened underneath so the number has something to sit on --
                // white on an arbitrary app icon is legible only by luck.
                .overlay {
                    if overflow > 0, index == visible.count - 1 {
                        ZStack {
                            RoundedRectangle(cornerRadius: 6, style: .continuous)
                                .fill(LocktyColors.background.opacity(0.66))

                            Text("+\(overflow)")
                                .font(.system(size: 11, weight: .semibold))
                                .foregroundStyle(LocktyColors.primaryText)
                        }
                    }
                }
                .zIndex(Double(visible.count - index))
            }
        }
    }

    /// The geometry every tile in the row gets, icons and overflow alike. Written once so
    /// the two cannot be given different numbers.
    private func slot<Content: View>(@ViewBuilder content: () -> Content) -> some View {
        content()
            .frame(width: iconSize, height: iconSize)
            .clipShape(RoundedRectangle(cornerRadius: 6, style: .continuous))
    }
}
