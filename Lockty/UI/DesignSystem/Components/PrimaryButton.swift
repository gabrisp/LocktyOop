import SwiftUI

struct PrimaryButton: View {
    let title: String
    let systemImage: String?
    /// Marks the button as "not yet" rather than merely disabled: it goes red and dims,
    /// so a gate that has to be waited out reads as a gate and not as a broken button.
    let isGated: Bool
    let action: () -> Void

    init(
        _ title: String,
        systemImage: String? = nil,
        isGated: Bool = false,
        action: @escaping () -> Void
    ) {
        self.title = title
        self.systemImage = systemImage
        self.isGated = isGated
        self.action = action
    }

    var body: some View {
        Button(action: action) {
            Label {
                Text(title)
                    .font(LocktyTypography.headline)
            } icon: {
                if let systemImage {
                    Image(systemName: systemImage)
                }
            }
        }
        .buttonStyle(.plain)
        .locktyPrimaryActionStyle(tint: isGated ? .red : LocktyColors.primaryText)
        .opacity(isGated ? 0.55 : 1)
        .animation(.smooth(duration: 0.28), value: isGated)
        .tappable()
    }
}
