import SwiftUI

struct SecondaryButton: View {
    let title: String
    let systemImage: String?
    let action: () -> Void

    init(_ title: String, systemImage: String? = nil, action: @escaping () -> Void) {
        self.title = title
        self.systemImage = systemImage
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
        .locktySecondaryActionStyle()
        .tappable()
    }
}
