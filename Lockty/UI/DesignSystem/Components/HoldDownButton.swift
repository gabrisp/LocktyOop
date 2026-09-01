import Combine
import SwiftUI

/// Hold-to-confirm pill with a fill that tracks the press, ported from the previous
/// Lockty. Starting a routine by hand is deliberate, so it takes a sustained press
/// rather than a tap.
///
/// When `sessionStartedAt` is set the same pill becomes a read-only elapsed-time
/// display: the routine is already running, so there is nothing left to confirm.
struct HoldDownButton: View {
    var text: String
    var sessionStartedAt: Date?
    var paddingHorizontal: CGFloat = 25
    var paddingVertical: CGFloat = 10
    /// Matches the unlock flow's primary: the same full-width capsule at the same
    /// height, so a commit looks like a commit wherever it is.
    var isProminent = false
    var duration: CGFloat = 1
    var scale: CGFloat = 0.95
    var action: () -> Void

    @State private var timer = Timer.publish(every: 0.01, on: .current, in: .common).autoconnect()
    @State private var timerCount: CGFloat = 0
    @State private var progress: CGFloat = 0
    @State private var isHolding = false
    @State private var isCompleted = false

    private var isDisplayOnly: Bool { sessionStartedAt != nil }

    var body: some View {
        labelContent
            .font(isProminent
                ? .system(.headline, design: .default, weight: .semibold)
                : LocktyTypography.body)
            .foregroundStyle(isProminent ? .black : LocktyColors.primaryText)
            .frame(maxWidth: isProminent ? .infinity : nil)
            .frame(height: isProminent ? 60 : nil)
            .padding(.vertical, isProminent ? 0 : paddingVertical)
            .padding(.horizontal, isProminent ? 0 : paddingHorizontal)
            .background {
                if isProminent {
                    Capsule().fill(LocktyColors.primaryText)
                }
            }
            .background {
                if !isDisplayOnly && !isCompleted {
                    GeometryReader { geometry in
                        Capsule()
                            // Over white the fill has to darken, not lighten, or the
                            // progress is invisible on the button it is filling.
                            .fill(isProminent ? Color.black.opacity(0.14) : LocktyColors.primaryText.opacity(0.14))
                            .frame(width: geometry.size.width * progress)
                            .frame(maxWidth: .infinity, alignment: .leading)
                    }
                }
            }
            .contentShape(Capsule())
            .safeGlass(radius: 999, interactive: !isDisplayOnly && !isProminent)
            .clipShape(Capsule())
            .allowsHitTesting(!isDisplayOnly)
            .scaleEffect(isHolding ? scale : 1)
            .animation(.snappy, value: isHolding)
            .onLongPressGesture(minimumDuration: duration) {
                guard !isDisplayOnly else { return }
                isHolding = false
                cancelTimer()
                withAnimation(.easeInOut(duration: 0.2)) { isCompleted = true }
                action()
            } onPressingChanged: { isPressing in
                guard !isDisplayOnly else { return }
                if isPressing {
                    isCompleted = false
                    reset()
                    isHolding = true
                    addTimer()
                }
            }
            .simultaneousGesture(
                // Releasing early anywhere cancels the fill.
                DragGesture(minimumDistance: 0)
                    .onEnded { _ in
                        guard !isCompleted else { return }
                        cancelTimer()
                        withAnimation(.snappy) { reset() }
                    }
            )
            .onReceive(timer) { _ in
                guard isHolding, progress != 1 else { return }
                timerCount += 0.01
                progress = max(min(timerCount / duration, 1), 0)
            }
            .onAppear(perform: cancelTimer)
            .sensoryFeedback(.impact(weight: .medium), trigger: isCompleted) { _, new in new }
    }

    @ViewBuilder
    private var labelContent: some View {
        if let sessionStartedAt {
            TimelineView(.periodic(from: .now, by: 1)) { _ in
                Text(elapsedText(since: sessionStartedAt))
                    .monospacedDigit()
            }
        } else {
            Text(text)
        }
    }

    private func elapsedText(since start: Date) -> String {
        let seconds = max(0, Int(Date().timeIntervalSince(start)))
        let hours = seconds / 3600
        let minutes = (seconds % 3600) / 60
        let remaining = seconds % 60
        if hours > 0 { return "\(hours)h \(minutes)m \(remaining)s" }
        if minutes > 0 { return "\(minutes)m \(remaining)s" }
        return "\(remaining)s"
    }

    private func addTimer() {
        timer = Timer.publish(every: 0.01, on: .current, in: .common).autoconnect()
    }

    private func cancelTimer() {
        timer.upstream.connect().cancel()
    }

    private func reset() {
        isHolding = false
        progress = 0
        timerCount = 0
    }
}
