import Combine
import SwiftUI

@MainActor
final class StreakViewModel: ObservableObject {
    @Published private(set) var summary: StreakSummary = .empty

    private let calculator: StreakCalculator
    private let routineExecutionRepository: RoutineExecutionRepository

    init(
        routineExecutionRepository: RoutineExecutionRepository,
        calculator: StreakCalculator = StreakCalculator()
    ) {
        self.routineExecutionRepository = routineExecutionRepository
        self.calculator = calculator
    }

    func load() async {
        let executions = (try? await routineExecutionRepository.executions(from: nil, to: nil)) ?? []
        let calendar = Calendar.current
        let routineDays = Set(executions.map { DayKey(date: $0.startedAt, calendar: calendar) })

        // Off the main actor: it reads every cached day in the container.
        let calculator = calculator
        let next = await Task.detached(priority: .userInitiated) {
            calculator.summary(routineDays: routineDays, calendar: calendar)
        }.value

        withAnimation(.smooth(duration: 0.35)) { summary = next }

        // Booked here because this is where the streak is actually known. Reading it is
        // the only moment the app can tell whether tonight needs a reminder at all.
        StreakReminderScheduler().refresh(
            isTodayEarned: next.isTodayEarned,
            current: next.current
        )
    }
}

/// The streak, on its own.
///
/// Centred and short, because it is one number and the two sentences that make it mean
/// something. A streak with no rule printed beside it is a slot machine: people cannot
/// tell what kept it, so they cannot tell what would keep it tomorrow.
struct StreakSheet: View {
    @ObservedObject var viewModel: StreakViewModel

    private var summary: StreakSummary { viewModel.summary }

    var body: some View {
        VStack(spacing: LocktySpacing.xl) {
            flame

            VStack(spacing: LocktySpacing.xs) {
                Text(summary.current == 1 ? "1 day" : "\(summary.current) days")
                    .font(.system(size: 44, weight: .bold))
                    .foregroundStyle(LocktyColors.primaryText)
                    .monospacedDigit()
                    .contentTransition(.numericText())

                Text(headline)
                    .font(.system(.subheadline, design: .default, weight: .regular))
                    .foregroundStyle(LocktyColors.secondaryText)
                    .multilineTextAlignment(.center)
                    .fixedSize(horizontal: false, vertical: true)
            }

            recentRow

            rules

            if summary.best > 0 {
                Text(summary.best == summary.current ? "This is your longest run yet." : "Your longest run is \(summary.best) days.")
                    .font(.system(.footnote, design: .default, weight: .regular))
                    .foregroundStyle(LocktyColors.tertiaryText)
                    .multilineTextAlignment(.center)
            }
        }
        .frame(maxWidth: .infinity)
        .padding(.horizontal, LocktySpacing.screenInset)
        .padding(.top, LocktySpacing.xl)
        .padding(.bottom, LocktySpacing.sheetBottom(forTop: LocktySpacing.md))
        .task { await viewModel.load() }
    }

    private var headline: String {
        if summary.current == 0 {
            return "Nothing going yet. Run a routine today, or come in under your usual, and it starts."
        }
        return summary.isTodayEarned
            ? "Today is in. Come back tomorrow."
            : "Today is not in yet -- yesterday's run is still standing."
    }

    @Environment(\.colorScheme) private var colorScheme

    /// The flame, lit by its own colour. Grey and unlit when there is no streak: a cold
    /// flame says what has happened more plainly than any sentence under it.
    private var flame: some View {
        let isLit = summary.current > 0
        let tint = isLit ? LocktyColors.warning : LocktyColors.neutral
        let isDark = colorScheme == .dark

        return ZStack {
            Circle()
                .fill(tint)
                .frame(width: 96, height: 96)
                .blur(radius: 28)
                .opacity(isLit ? (isDark ? 0.6 : 0.3) : 0.12)
                .blendMode(isDark ? .plusLighter : .normal)

            Image(systemName: isLit ? "flame.fill" : "flame")
                .font(.system(size: 46, weight: .regular))
                .foregroundStyle(tint)
        }
        .frame(height: 96)
        .animation(.smooth(duration: 0.5), value: isLit)
    }

    /// The fortnight behind you, one mark per day, oldest first.
    private var recentRow: some View {
        HStack(spacing: 6) {
            ForEach(Array(summary.recentDays.enumerated()), id: \.offset) { _, earned in
                Capsule(style: .continuous)
                    .fill(earned ? LocktyColors.warning : LocktyColors.ink(0.10))
                    .frame(height: 26)
            }
        }
        .frame(maxWidth: .infinity)
    }

    /// What actually keeps it. Both ways, said plainly, with how often each one has been
    /// the thing that carried the day.
    private var rules: some View {
        VStack(spacing: 0) {
            rule(
                systemImage: "play.circle",
                title: "Run a routine",
                detail: summary.daysWithRoutine == 0
                    ? "Any routine, any length."
                    : "\(summary.daysWithRoutine) of the last 90 days"
            )

            Divider().overlay(LocktyColors.separator.opacity(0.45))

            rule(
                systemImage: "arrow.down.right",
                title: "Or come in under your usual",
                detail: summary.daysUnderUsual == 0
                    ? "Less screen time than your recent average."
                    : "\(summary.daysUnderUsual) of the last 90 days"
            )
        }
        .padding(.horizontal, LocktySpacing.cardInset)
        .locktyCardBackground(cornerRadius: 26)
    }

    private func rule(systemImage: String, title: String, detail: String) -> some View {
        HStack(spacing: LocktySpacing.md) {
            Image(systemName: systemImage)
                .font(.system(size: 15, weight: .regular))
                .foregroundStyle(LocktyColors.secondaryText)
                .frame(width: 24)

            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(.system(.subheadline, design: .default, weight: .semibold))
                    .foregroundStyle(LocktyColors.primaryText)

                Text(detail)
                    .font(.system(.footnote, design: .default, weight: .regular))
                    .foregroundStyle(LocktyColors.secondaryText)
            }

            Spacer(minLength: 0)
        }
        .frame(minHeight: 60)
    }
}
