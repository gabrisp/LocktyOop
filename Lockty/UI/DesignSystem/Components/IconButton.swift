import SwiftUI

enum IconButtonChrome {
    case plain
    case filled
}

struct IconButton: View {
    let systemImage: String
    let accessibilityLabel: String
    let chrome: IconButtonChrome
    let size: CGFloat
    let action: () -> Void

    init(
        systemImage: String,
        accessibilityLabel: String,
        chrome: IconButtonChrome = .filled,
        size: CGFloat = 44,
        action: @escaping () -> Void
    ) {
        self.systemImage = systemImage
        self.accessibilityLabel = accessibilityLabel
        self.chrome = chrome
        self.size = size
        self.action = action
    }

    var body: some View {
        Button(action: action) {
            Image(systemName: systemImage)
                .font(.system(size: 17, weight: .medium))
                .frame(width: size, height: size)
        }
        .buttonStyle(.plain)
        .foregroundStyle(LocktyColors.primaryText)
        .modifier(IconButtonChromeModifier(chrome: chrome))
        .accessibilityLabel(accessibilityLabel)
        .tappable()
    }
}

private struct IconButtonChromeModifier: ViewModifier {
    let chrome: IconButtonChrome

    @ViewBuilder
    func body(content: Content) -> some View {
        switch chrome {
        case .plain:
            content
        case .filled:
            content
                .safeGlass(radius: 22, interactive: true)
                .clipShape(Circle())
        }
    }
}
