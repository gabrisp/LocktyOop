import SwiftUI

/// Wrapper for the sheets that replaced the old tabs: a title, the section's own
/// content, and nothing else — no navigation chrome.
struct LocktySectionSheet<Content: View>: View {
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
        .presentationDetents([.large])
        .presentationDragIndicator(.visible)
    }
}
