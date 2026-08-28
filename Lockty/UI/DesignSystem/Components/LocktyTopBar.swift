import SwiftUI

struct LocktyTopBar<Leading: View, Trailing: View>: View {
    let title: String
    let leading: Leading
    let trailing: Trailing

    init(
        title: String,
        @ViewBuilder leading: () -> Leading,
        @ViewBuilder trailing: () -> Trailing
    ) {
        self.title = title
        self.leading = leading()
        self.trailing = trailing()
    }

    var body: some View {
        HStack(spacing: LocktySpacing.md) {
            leading
                .frame(minWidth: 44, alignment: .leading)

            Spacer(minLength: 0)

            Text(title)
                .font(.title3.weight(.regular))
                .foregroundStyle(LocktyColors.primaryText)
                .lineLimit(1)

            Spacer(minLength: 0)

            trailing
                .frame(minWidth: 44, alignment: .trailing)
        }
        .padding(.horizontal, LocktySpacing.md)
        .padding(.top, LocktySpacing.xs)
        .padding(.bottom, LocktySpacing.sm)
    }
}

struct LocktyTopBarIconAction: View {
    let systemImage: String
    let label: String
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Image(systemName: systemImage)
        }
        .buttonStyle(.plain)
        .locktySheetDismissStyle()
        .accessibilityLabel(label)
    }
}

struct LocktyTopBarTextAction: View {
    let title: String
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Text(title)
                .font(.subheadline.weight(.medium))
                .foregroundStyle(LocktyColors.primaryText)
                .padding(.horizontal, LocktySpacing.md)
                .frame(height: 36)
                .safeGlass(radius: 18, interactive: true)
        }
        .buttonStyle(.plain)
        .tappable()
    }
}
