import SwiftUI

struct PrimaryButton: View {
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
            .frame(maxWidth: .infinity)
            .padding(.vertical, LocktySpacing.md)
            .padding(.horizontal, LocktySpacing.lg)
        }
        .buttonStyle(.plain)
        .foregroundStyle(.black)
        .background(.tint, in: RoundedRectangle(cornerRadius: LocktyRadius.medium, style: .continuous))
        .tappable()
    }
}
