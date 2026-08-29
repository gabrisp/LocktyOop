import SwiftUI

/// Wrapper for the screens that replaced the old tabs. They're pushed onto the
/// navigation stack, so their own sheets (editors, pickers) present on top of them.
struct LocktySectionScreen<Content: View>: View {
    let title: String
    @ViewBuilder var content: Content

    var body: some View {
        // The title lives in the navigation bar, not in the scroll content: these are
        // pushed screens, so the native inline title sits next to the native back
        // button instead of being duplicated as a large heading underneath it.
        ScrollView(.vertical, showsIndicators: false) {
            VStack(alignment: .leading, spacing: LocktySpacing.lg) {
                content
            }
            .padding(.horizontal, LocktySpacing.lg)
            .padding(.vertical, LocktySpacing.lg)
        }
        .locktyScreenBackground()
        .navigationTitle(title)
        .navigationBarTitleDisplayMode(.inline)
    }
}
