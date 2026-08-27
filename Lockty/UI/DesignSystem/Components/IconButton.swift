import SwiftUI

struct IconButton: View {
    let systemImage: String
    let accessibilityLabel: String
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Image(systemName: systemImage)
                .font(.system(size: 17, weight: .semibold))
                .frame(width: 44, height: 44)
        }
        .buttonStyle(.plain)
        .foregroundStyle(LocktyColors.primaryText)
        .safeGlass(radius: 22, interactive: true)
        .accessibilityLabel(accessibilityLabel)
        .tappable()
    }
}
