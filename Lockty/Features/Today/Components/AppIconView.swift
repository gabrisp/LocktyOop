import SwiftUI
import FamilyControls
import ManagedSettings

struct AppIconView: View {
    let source: AppIconSource
    let applicationToken: ManagedSettings.ApplicationToken?
    let fallbackSystemImage: String?
    var size: CGFloat = 38

    private var shape: RoundedRectangle {
        RoundedRectangle(cornerRadius: size * 0.24, style: .continuous)
    }

    var body: some View {
        Group {
            if case .screenTimeToken = source, let applicationToken {
                Label(applicationToken)
                    .labelStyle(.iconOnly)
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
        .clipShape(shape)
        .overlay {
            shape.stroke(.white.opacity(0.10), lineWidth: 0.5)
        }
        .accessibilityHidden(true)
    }

    private var placeholder: some View {
        shape
            .fill(LocktyColors.elevatedBackground)
            .overlay {
                ProgressView()
                    .controlSize(.mini)
                    .tint(LocktyColors.secondaryText)
            }
    }

    private var fallbackIcon: some View {
        shape
            .fill(LocktyColors.elevatedBackground)
            .overlay {
                Image(systemName: fallbackSystemImage ?? "app.dashed")
                    .font(.system(size: size * 0.42, weight: .semibold))
                    .foregroundStyle(LocktyColors.primaryText)
            }
    }
}
