import FamilyControls
import ManagedSettings
import SwiftUI

/// Anything that has to sit in a row of app icons and be the same size as them: the
/// "+N" tile at the end of a stack, an empty slot in a folder, a tinted stand-in.
///
/// FamilyControls draws `Label(token)` at its own size and ignores whatever frame it is
/// handed, so a placeholder built from a `RoundedRectangle` at some chosen number is only
/// ever the same size as the icons beside it by coincidence -- and stops being so the
/// moment anything scales them. This fills a rectangle in whatever colour is wanted and
/// masks it with a real token, so the placeholder inherits an icon's exact silhouette and
/// size, whatever the system decided those are.
///
/// The token is a stencil and nothing else: none of it is drawn, only its shape is used,
/// so any token to hand will do.
struct LocktyTokenPlaceholder: View {
    /// Any app icon. Only its shape is used, never its picture.
    let stencil: ApplicationToken?
    /// What the placeholder is filled with. A flat colour, a tint at low opacity, a
    /// routine's accent -- whatever the row it belongs to calls for.
    var fill: Color = LocktyColors.elevatedBackground

    var body: some View {
        // The hidden label is what claims the space. A masked Rectangle on its own is
        // flexible -- a mask changes what is drawn, never what is laid out -- so it would
        // stretch to whatever it was offered instead of taking an icon's size.
        icon
            .opacity(0)
            .overlay {
                Rectangle()
                    .fill(fill)
                    .mask { icon }
            }
    }

    @ViewBuilder
    private var icon: some View {
        if let stencil {
            Label(stencil)
                .labelStyle(.iconOnly)
                .id(stencil)
        } else {
            // No app to take a shape from, so a square stands in. Only reached when the
            // row has nothing in it, which means no overflow tile is drawn either.
            RoundedRectangle(cornerRadius: 6, style: .continuous)
                .frame(width: 22, height: 22)
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
                .zIndex(Double(visible.count - index))
            }

            if overflow > 0 {
                slot {
                    LocktyTokenPlaceholder(stencil: visible.first)
                }
                .overlay {
                    Text("+\(overflow)")
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundStyle(LocktyColors.primaryText)
                }
                .zIndex(0)
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
