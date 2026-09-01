import SwiftUI
import FamilyControls
import ManagedSettings

enum AppIconChrome {
    case plain
    case framed
}

struct AppIconView: View {
    let source: AppIconSource
    let applicationToken: ManagedSettings.ApplicationToken?
    let fallbackSystemImage: String?
    var size: CGFloat = 38
    var chrome: AppIconChrome = .framed

    private var shape: RoundedRectangle {
        RoundedRectangle(cornerRadius: size * 0.24, style: .continuous)
    }

    var body: some View {
        Group {
            if case .screenTimeToken = source, let applicationToken {
                tokenIcon(for: applicationToken)
            } else if let url = source.remoteURL {
                AsyncImage(url: url) { phase in
                    switch phase {
                    case .empty:
                        placeholder
                    case .success(let image):
                        image
                            .resizable()
                            .scaledToFill()
                    case .failure:
                        fallbackIcon
                    @unknown default:
                        fallbackIcon
                    }
                }
            } else {
                fallbackIcon
            }
        }
        .frame(width: size, height: size)
        .modifier(AppIconChromeModifier(chrome: chrome, shape: shape))
        .accessibilityHidden(true)
    }

    private func tokenIcon(for applicationToken: ManagedSettings.ApplicationToken) -> some View {
        let baseSize: CGFloat = chrome == .plain ? 28 : 32
        let scale = max(size / baseSize, 1)

        return Label(applicationToken)
            .labelStyle(.iconOnly)
            .font(.system(size: size * 0.8, weight: .regular))
            .scaleEffect(scale)
            .frame(width: size, height: size)
            .clipped()
    }

    private var placeholder: some View {
        Group {
            if chrome == .plain {
                ProgressView()
                    .controlSize(.mini)
                    .tint(LocktyColors.secondaryText)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                shape
                    .fill(LocktyColors.elevatedBackground)
                    .overlay {
                        ProgressView()
                            .controlSize(.mini)
                            .tint(LocktyColors.secondaryText)
                    }
            }
        }
    }

    private var fallbackIcon: some View {
        Group {
            if chrome == .plain {
                Image(systemName: fallbackSystemImage ?? "app.dashed")
                    .font(.system(size: size * 0.42, weight: .semibold))
                    .foregroundStyle(LocktyColors.primaryText)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                shape
                    .fill(LocktyColors.elevatedBackground)
                    .overlay {
                        Image(systemName: fallbackSystemImage ?? "app.dashed")
                            .font(.system(size: size * 0.42, weight: .semibold))
                            .foregroundStyle(LocktyColors.primaryText)
                    }
            }
        }
    }
}

private struct AppIconChromeModifier: ViewModifier {
    let chrome: AppIconChrome
    let shape: RoundedRectangle

    func body(content: Content) -> some View {
        switch chrome {
        case .plain:
            content
        case .framed:
            content
                .clipShape(shape)
                .overlay {
                    shape.stroke(LocktyColors.ink(0.10), lineWidth: 0.5)
                }
        }
    }
}
