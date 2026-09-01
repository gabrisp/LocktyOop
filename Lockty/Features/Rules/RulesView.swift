import FamilyControls
import ManagedSettings
import SwiftUI

struct RulesView: View {
    @ObservedObject var viewModel: RulesViewModel
    let router: AppRouter

    private let columns = [
        GridItem(.flexible(), spacing: RoutineGridMetrics.spacing),
        GridItem(.flexible(), spacing: RoutineGridMetrics.spacing)
    ]

    var body: some View {
        LazyVGrid(columns: columns, spacing: RoutineGridMetrics.spacing) {
            ForEach(viewModel.rules) { rule in
                if let routine = rule.routineBridge {
                    RoutineCard(
                        routine: routine,
                        isActive: viewModel.activeScheduleRuleIDs().contains(rule.id),
                        applicationTokens: viewModel.tokens(for: rule.id)
                    ) {
                        router.presentSheet(.routineEditor(RoutineEditorRoute(routineID: rule.id)))
                    }
                } else {
                    RuleCard(rule: rule, applicationTokens: viewModel.tokens(for: rule.id)) {
                        router.presentSheet(.ruleEditor(RuleEditorRoute(ruleID: rule.id)))
                    }
                }
            }

            addRuleTile
        }
        .onAppear {
            Task { await viewModel.load() }
        }
        .onChange(of: router.sheet) { _, newValue in
            guard newValue == nil else { return }
            Task { await viewModel.load() }
        }
        .alert(
            "Rule action failed",
            isPresented: Binding(
                get: { viewModel.errorMessage != nil },
                set: { if !$0 { viewModel.clearError() } }
            )
        ) {
            Button("OK", role: .cancel) {
                viewModel.clearError()
            }
        } message: {
            Text(viewModel.errorMessage ?? "")
        }
    }

    private var addRuleTile: some View {
        Button {
            router.presentSheet(.ruleEditor(RuleEditorRoute(ruleID: nil)))
        } label: {
            CardView(interactive: true, height: RoutineGridMetrics.tileHeight) {
                VStack(alignment: .leading, spacing: LocktySpacing.md) {
                    Image(systemName: "plus")
                        .font(.system(size: 16, weight: .light))
                        .foregroundStyle(LocktyColors.primaryText)
                        .frame(width: 24, height: 24)

                    Spacer(minLength: 0)

                    Text("Add Rule")
                        .font(LocktyTypography.headline)
                        .foregroundStyle(LocktyColors.primaryText)
                        .lineLimit(1)
                }
            }
        }
        .buttonStyle(.plain)
        .tappable()
    }
}

struct RuleCard: View {
    let rule: Rule
    let applicationTokens: [ApplicationToken]
    let onOpen: () -> Void

    private var accent: Color {
        switch rule.kind {
        case .schedule:
            LocktyColors.productive
        case .openCountLimit:
            LocktyColors.warning
        case .dailyUsageLimit:
            LocktyColors.primaryText
        case .sessionDurationLimit:
            LocktyColors.secondaryText
        }
    }

    private var kindSymbol: String {
        switch rule.kind {
        case .schedule:
            "calendar"
        case .openCountLimit:
            "number.circle"
        case .dailyUsageLimit:
            "hourglass"
        case .sessionDurationLimit:
            "timer"
        }
    }

    private var pillText: String {
        switch rule.kind {
        case .schedule:
            return "Schedule"
        case .openCountLimit:
            if let configuration = rule.openCountLimitConfiguration {
                return "\(configuration.maximumOpens) opens / \(configuration.windowHours)h"
            }
        case .dailyUsageLimit:
            if let configuration = rule.dailyUsageLimitConfiguration {
                return "\(configuration.maximumMinutesPerDay) min / day"
            }
        case .sessionDurationLimit:
            if let configuration = rule.sessionDurationLimitConfiguration {
                return "\(configuration.maximumMinutesPerSession) min / session"
            }
        }
        return rule.kind.title
    }

    var body: some View {
        Button(action: onOpen) {
            CardView(
                radius: RoutineGridMetrics.tileRadius,
                interactive: true,
                height: RoutineGridMetrics.tileHeight
            ) {
                VStack(alignment: .leading, spacing: LocktySpacing.sm) {
                    HStack {
                        Image(systemName: kindSymbol)
                            .font(.system(size: 16, weight: .light))
                            .foregroundStyle(LocktyColors.primaryText)
                            .frame(width: 32, height: 32)
                            .background(Circle().fill(accent.opacity(0.18)))

                        Spacer(minLength: 0)

                        Text(rule.isEnabled ? "ON" : "OFF")
                            .locktyEyebrow()
                            .foregroundStyle(rule.isEnabled ? accent : LocktyColors.secondaryText)
                    }

                    Spacer(minLength: 0)

                    Text(pillText)
                        .font(.system(.caption, design: .default, weight: .medium))
                        .foregroundStyle(LocktyColors.primaryText)
                        .lineLimit(1)
                        .padding(.horizontal, LocktySpacing.sm)
                        .padding(.vertical, 5)
                        .overlay {
                            Capsule(style: .continuous)
                                .stroke(accent.opacity(0.34), lineWidth: 1)
                        }

                    Text(rule.name)
                        .font(.system(.subheadline, design: .default, weight: .bold))
                        .foregroundStyle(LocktyColors.primaryText)
                        .lineLimit(1)

                    HStack(spacing: LocktySpacing.xs) {
                        Text("Bloquear")
                            .font(.system(.caption, design: .default, weight: .regular))
                            .foregroundStyle(LocktyColors.secondaryText)
                            .lineLimit(1)

                        LocktyStackedAppTokens(tokens: applicationTokens)

                        Spacer(minLength: 0)
                    }
                }
            }
            .overlay {
                RoundedRectangle(cornerRadius: RoutineGridMetrics.tileRadius, style: .continuous)
                    .stroke(accent.opacity(0.16), lineWidth: 1)
            }
        }
        .buttonStyle(.locktyInteractive)
        .tappable()
    }
}
