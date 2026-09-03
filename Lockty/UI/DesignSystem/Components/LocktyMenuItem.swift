import SwiftUI

/// One row of a menu, or of a list that behaves like one.
///
/// Written once because the rows were written a dozen times: a Button, a `.plain` style
/// and an HStack, which meant a press did nothing at all -- `.plain` is the style that
/// exists to remove feedback. The rows in the sheets already light and shrink under a
/// finger, and the menus opening on top of them did not, so the same tap felt live in one
/// place and dead in the next.
///
/// The surface is drawn in the row's own rounded rectangle rather than across the panel,
/// which is what makes it read as *this* item answering. A long press is optional and
/// carries its own success haptic, for the menus where holding a row means something more
/// than choosing it.
struct LocktyMenuItem<Content: View>: View {
    var isSelected = false
    var longPressAction: (() -> Void)?
    let action: () -> Void
    @ViewBuilder var content: Content

    /// Matches the panel's own 22 minus its inset, so the highlight sits inside the menu's
    /// corner rather than cutting across it.
    private var shape: RoundedRectangle {
        RoundedRectangle(cornerRadius: 14, style: .continuous)
    }

    var body: some View {
        Button(action: action) {
            HStack(spacing: LocktySpacing.md) {
                content

                Spacer(minLength: 0)

                if isSelected {
                    Image(systemName: "checkmark")
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundStyle(LocktyColors.productive)
                }
            }
            .padding(.horizontal, LocktySpacing.md)
            .frame(minHeight: 46)
            .contentShape(shape)
        }
        .buttonStyle(.locktyInteractive(shape: shape))
        .tappable()
        .locktyMenuItemLongPress(longPressAction)
    }
}

private extension View {
    /// Attached only when there is something to hold for. A gesture that does nothing
    /// still swallows the press it was given, which would make an ordinary tap feel slow.
    ///
    /// Lights the row's content rather than drawing a shape behind it. A menu row is
    /// small, and a rectangle around one is mostly rectangle.
    @ViewBuilder
    func locktyMenuItemLongPress(_ action: (() -> Void)?) -> some View {
        if let action {
            locktyLongPress(minimumDuration: 0.4, action: action)
        } else {
            self
        }
    }
}

extension LocktyMenuItem where Content == LocktyMenuItemLabel {
    /// The common case: a title, and a line under it when there is something to add.
    init(
        title: String,
        subtitle: String? = nil,
        isSelected: Bool = false,
        longPressAction: (() -> Void)? = nil,
        action: @escaping () -> Void
    ) {
        self.init(
            isSelected: isSelected,
            longPressAction: longPressAction,
            action: action
        ) {
            LocktyMenuItemLabel(title: title, subtitle: subtitle)
        }
    }
}

struct LocktyMenuItemLabel: View {
    let title: String
    var subtitle: String?

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(title)
                .font(.system(.subheadline, design: .default, weight: .regular))
                .foregroundStyle(LocktyColors.primaryText)

            if let subtitle {
                Text(subtitle)
                    .font(.system(.footnote, design: .default, weight: .regular))
                    .foregroundStyle(LocktyColors.secondaryText)
                    .lineLimit(2)
            }
        }
    }
}
