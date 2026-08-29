import SwiftUI

/// The live counterpart of a My Day entry: same shape of information, but for the
/// session happening right now, so the values tick instead of being fixed.
struct LiveSessionSheet: View {
    let routine: ActiveRoutine
    let pauseEvents: [PauseEvent]
    let onStop: () -> Void

    var body: some View {
        LocktyDynamicSheet {
            VStack(alignment: .leading, spacing: LocktySpacing.lg) {
                header

                VStack(spacing: LocktySpacing.sm) {
                    TimelineView(.periodic(from: .now, by: 1)) { _ in
                        row("Elapsed", elapsedText)
                    }
                    row("Started", routine.startedAt.formatted(date: .omitted, time: .shortened))
                    row("Pauses", pauseEvents.isEmpty ? "None" : "\(pauseEvents.count)")
                    row(
                        "Tasks",
                        routine.taskCompletions.isEmpty
                            ? "None"
                            : "\(routine.taskCompletions.filter { $0.completedAt != nil }.count)/\(routine.taskCompletions.count)"
                    )
                }

                if !pauseEvents.isEmpty {
                    VStack(alignment: .leading, spacing: LocktySpacing.sm) {
                        Text("PAUSES THIS SESSION")
                            .locktyEyebrow()

                        ForEach(pauseEvents.prefix(5)) { event in
                            HStack {
                                Text(event.application.displayName)
                                    .font(LocktyTypography.callout)
                                    .foregroundStyle(LocktyColors.primaryText)
                                    .lineLimit(1)
                                Spacer(minLength: LocktySpacing.md)
                                Text(event.decision.rawValue.capitalized)
                                    .font(LocktyTypography.caption)
                                    .foregroundStyle(
                                        event.decision == .abandoned
                                            ? LocktyColors.productive
                                            : LocktyColors.secondaryText
                                    )
                            }
                        }
                    }
                }

                Button(role: .destructive, action: onStop) {
                    Text("Stop Routine")
                }
                .buttonStyle(.plain)
                .locktySecondaryActionStyle()
            }
            .padding(LocktySpacing.lg)
        }
        .presentationDragIndicator(.visible)
    }

    private var header: some View {
        HStack(spacing: LocktySpacing.md) {
            Capsule()
                .fill(LocktyColors.productive)
                .frame(width: 4, height: 38)

            VStack(alignment: .leading, spacing: 2) {
                Text(routine.nameSnapshot)
                    .font(.title3.weight(.regular))
                    .foregroundStyle(LocktyColors.primaryText)
                    .lineLimit(1)

                Text(routine.modeSnapshot == .strict ? "Strict routine" : "Normal routine")
                    .font(LocktyTypography.caption)
                    .foregroundStyle(LocktyColors.secondaryText)
            }

            Spacer(minLength: 0)
        }
    }

    private func row(_ label: String, _ value: String) -> some View {
        HStack {
            Text(label)
                .foregroundStyle(LocktyColors.secondaryText)
            Spacer(minLength: LocktySpacing.md)
            Text(value)
                .foregroundStyle(LocktyColors.primaryText)
                .monospacedDigit()
        }
        .font(LocktyTypography.callout)
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
