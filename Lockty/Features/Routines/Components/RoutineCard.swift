import SwiftUI

/// Grid tile for a routine: icon, name, and a short restriction summary.
struct RoutineCard: View {
    let routine: Routine
    let isActive: Bool
    let onOpen: () -> Void

    private var subtitle: String {
        let apps = routine.blockedApplications.count
        let domains = routine.blockedDomains.count
        let appsText = apps == 1 ? "1 app" : "\(apps) apps"
        guard domains > 0 else { return appsText }
        return "\(appsText) · \(domains == 1 ? "1 site" : "\(domains) sites")"
    }

    var body: some View {
        Button(action: onOpen) {
            CardView(interactive: true, height: RoutineGridMetrics.tileHeight) {
                VStack(alignment: .leading, spacing: LocktySpacing.md) {
                    HStack {
                        Image(systemName: routine.icon?.isEmpty == false ? routine.icon! : "repeat")
                            .font(.system(size: 16, weight: .light))
                            .foregroundStyle(LocktyColors.primaryText)
                            .frame(width: 24, height: 24)

                        Spacer(minLength: 0)

                        if isActive {
                            Text("ACTIVE")
                                .locktyEyebrow()
                                .foregroundStyle(LocktyColors.productive)
                        }
                    }

                    Spacer(minLength: 0)

                    VStack(alignment: .leading, spacing: 2) {
                        Text(routine.name)
                            .font(LocktyTypography.headline)
                            .foregroundStyle(LocktyColors.primaryText)
                            .lineLimit(1)

                        Text(subtitle)
                            .font(LocktyTypography.caption)
                            .foregroundStyle(LocktyColors.secondaryText)
                            .lineLimit(1)
                    }
                }
            }
        }
        .buttonStyle(.plain)
        .tappable()
    }
}

enum RoutineGridMetrics {
    static let tileHeight: CGFloat = 108
    static let spacing = LocktySpacing.sm
}
