import SwiftUI

/// Persistent bottom bar summarising whatever is running right now, tapped to open the
/// live session sheet. Only shown while something is actually active.
struct ActiveSessionBar: View {
    let routine: ActiveRoutine
    let pauseCount: Int
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: LocktySpacing.md) {
                Image(systemName: routine.iconName)
                    .font(.system(size: 16, weight: .light))
                    .foregroundStyle(LocktyColors.primaryText)
                    .frame(width: 28, height: 28)

                VStack(alignment: .leading, spacing: 1) {
                    Text(routine.nameSnapshot)
                        .font(LocktyTypography.headline)
                        .foregroundStyle(LocktyColors.primaryText)
                        .lineLimit(1)

                    Text(pauseCount == 1 ? "1 pause" : "\(pauseCount) pauses")
                        .font(LocktyTypography.caption)
                        .foregroundStyle(LocktyColors.secondaryText)
                        .lineLimit(1)
                }

                Spacer(minLength: 0)

                // Driven by a timeline rather than stored state so it ticks without the
                // rest of the screen re-rendering.
                TimelineView(.periodic(from: .now, by: 1)) { _ in
                    Text(elapsedText)
                        .font(.system(size: 17, weight: .light, design: .rounded))
                        .monospacedDigit()
                        .foregroundStyle(LocktyColors.primaryText)
                }
            }
            .padding(.horizontal, LocktySpacing.md)
            .frame(height: 56)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .tappable()
        .safeGlass(radius: 28, interactive: true)
        .clipShape(RoundedRectangle(cornerRadius: 28, style: .continuous))
        .padding(.horizontal, LocktySpacing.md)
    }

    private var elapsedText: String {
        let seconds = max(0, Int(Date().timeIntervalSince(routine.startedAt)))
        let hours = seconds / 3600
        let minutes = (seconds % 3600) / 60
        let remaining = seconds % 60
        if hours > 0 {
            return String(format: "%d:%02d:%02d", hours, minutes, remaining)
        }
        return String(format: "%d:%02d", minutes, remaining)
    }
}

private extension ActiveRoutine {
    var iconName: String { "repeat" }
}
