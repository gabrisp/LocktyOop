import SwiftUI

/// The one way a section is titled: an uppercase eyebrow caption sitting above the
/// section's card, optionally preceded by a hairline separator, and optionally carrying
/// an (i) that explains the section in a popover.
///
/// Explanations live behind the (i) rather than as body copy under the title, so a
/// section stays visually quiet by default and every section explains itself the same way.
struct LocktySectionTitle: View {
    let title: String
    var info: String?
    var showsSeparator = true
    /// Optional trailing content, e.g. a count.
    var accessory: AnyView?
    /// Set when the section has a screen of its own. The title then reads as the way in:
    /// it grows to a real heading, carries a chevron, and the whole row is tappable.
    var onOpen: (() -> Void)?
    /// Sits immediately after the title rather than at the trailing edge -- for marks
    /// that belong to the words, like a live indicator, not for trailing counts.
    var inlineAccessory: AnyView?
    /// Draws the heading style and its chevron without taking the tap itself, for cards
    /// that are already a button in their entirety.
    var showsChevron = false
    /// Uses the larger inline title styling without falling back to the old eyebrow.
    var usesProminentStyle = false

    @State private var isShowingInfo = false

    init(
        _ title: String,
        info: String? = nil,
        showsSeparator: Bool = true
    ) {
        self.title = title
        self.info = info
        self.showsSeparator = showsSeparator
        self.accessory = nil
    }

    init(
        _ title: String,
        info: String? = nil,
        onOpen: @escaping () -> Void
    ) {
        self.title = title
        self.info = info
        self.showsSeparator = false
        self.accessory = nil
        self.onOpen = onOpen
    }

    /// The heading form for a card that handles its own tap.
    init<Inline: View>(
        _ title: String,
        showsChevron: Bool,
        @ViewBuilder inlineAccessory: () -> Inline
    ) {
        self.title = title
        self.showsSeparator = false
        self.accessory = nil
        self.showsChevron = showsChevron
        self.inlineAccessory = AnyView(inlineAccessory())
    }

    init(_ title: String, showsChevron: Bool) {
        self.title = title
        self.showsSeparator = false
        self.accessory = nil
        self.showsChevron = showsChevron
    }

    init(_ title: String, prominent: Bool, showsChevron: Bool = false) {
        self.title = title
        self.showsSeparator = false
        self.accessory = nil
        self.showsChevron = showsChevron
        self.usesProminentStyle = prominent
    }

    init<Inline: View>(
        _ title: String,
        info: String? = nil,
        onOpen: @escaping () -> Void,
        @ViewBuilder inlineAccessory: () -> Inline
    ) {
        self.title = title
        self.info = info
        self.showsSeparator = false
        self.accessory = nil
        self.onOpen = onOpen
        self.inlineAccessory = AnyView(inlineAccessory())
    }

    init<Accessory: View>(
        _ title: String,
        info: String? = nil,
        showsSeparator: Bool = true,
        @ViewBuilder accessory: () -> Accessory
    ) {
        self.title = title
        self.info = info
        self.showsSeparator = showsSeparator
        self.accessory = AnyView(accessory())
    }

    var body: some View {
        VStack(alignment: .leading, spacing: LocktySpacing.sm) {
            if showsSeparator {
                Rectangle()
                    .fill(LocktyColors.separator)
                    .frame(height: 0.5)
            }

            HStack(spacing: LocktySpacing.sm) {
                if onOpen != nil || showsChevron || usesProminentStyle {
                    // The usage card's heading, verbatim -- it is the one every other
                    // card matches, not the other way round.
                    // subheadline over headline, and footnote over subheadline for the
                    // chevron: exactly one step down each, which keeps Dynamic Type
                    // rather than pinning a point size to take 2pt off.
                    Text(title)
                        .font(.system(.subheadline, design: .default, weight: .semibold))
                        .foregroundStyle(LocktyColors.ink(0.72))
                        .lineLimit(1)

                    if onOpen != nil || showsChevron {
                        Image(systemName: "chevron.right")
                            .font(.system(.footnote, design: .default, weight: .medium))
                            .foregroundStyle(LocktyColors.ink(0.58))
                    }

                    inlineAccessory
                        .padding(.leading, LocktySpacing.xs)
                } else {
                    Text(title.uppercased())
                        .locktyEyebrow()
                }

                if let info {
                    Button {
                        isShowingInfo = true
                    } label: {
                        Image(systemName: "info.circle")
                            .font(.system(size: 13, weight: .light))
                            .foregroundStyle(LocktyColors.tertiaryText)
                    }
                    .buttonStyle(.plain)
                    .tappable()
                    .locktyMenu(isPresented: $isShowingInfo) {
                        Text(info)
                            .font(LocktyTypography.callout)
                            .foregroundStyle(LocktyColors.primaryText)
                            .frame(width: 240, alignment: .leading)
                            .padding(LocktySpacing.md)
                    }
                }

                Spacer(minLength: 0)

                accessory
            }
            .contentShape(Rectangle())
            .onTapGesture {
                onOpen?()
            }
        }
    }
}
