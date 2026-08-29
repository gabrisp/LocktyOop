import SwiftUI

/// Wrapper for the screens that replaced the old tabs. They're pushed onto the
/// navigation stack, so their own sheets (editors, pickers) present on top of them.
struct LocktySectionScreen<Content: View>: View {
    let title: String
    @ViewBuilder var content: Content

    var body: some View {
        ScrollView(.vertical, showsIndicators: false) {
            VStack(alignment: .leading, spacing: LocktySpacing.lg) {
                Text(title)
                    .font(LocktyTypography.largeTitle)
                    .foregroundStyle(LocktyColors.primaryText)

                content
            }
            .padding(.horizontal, LocktySpacing.md)
            .padding(.vertical, LocktySpacing.lg)
        }
        .locktyScreenBackground()
        .toolbarVisibility(.hidden, for: .navigationBar)
    }
}
