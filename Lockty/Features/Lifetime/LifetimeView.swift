import SwiftUI

struct LifetimeView: View {
    @Bindable var viewModel: LifetimeViewModel
    @Bindable var router: AppRouter

    var body: some View {
        ScrollView(showsIndicators: false) {
            VStack(alignment: .leading, spacing: LocktySpacing.lg) {
                Text("Lifetime")
                    .font(LocktyTypography.largeTitle)
                    .foregroundStyle(LocktyColors.primaryText)

                CardView {
                    VStack(alignment: .leading, spacing: LocktySpacing.xs) {
                        Text("LIFE BACK")
                            .font(LocktyTypography.caption)
                            .foregroundStyle(LocktyColors.secondaryText)
                        Text(viewModel.state.reclaimedTime)
                            .font(LocktyTypography.largeTitle)
                            .foregroundStyle(LocktyColors.primaryText)
                            .locktyNumericTransition(trigger: viewModel.state.reclaimedTime)
                        Text("reclaimed since joining Lockty")
                            .font(LocktyTypography.callout)
                            .foregroundStyle(LocktyColors.secondaryText)
                        Text(viewModel.state.baselineText)
                            .font(LocktyTypography.caption)
                            .foregroundStyle(LocktyColors.tertiaryText)
                    }
                }

                if case .insufficient(let message) = viewModel.state.loadingState {
                    CardView {
                        Text(message)
                            .font(LocktyTypography.callout)
                            .foregroundStyle(LocktyColors.secondaryText)
                    }
                }

                SectionHeader(title: "Current Pace")
                CardView {
                    HStack {
                        Text(viewModel.state.currentPace)
                            .font(LocktyTypography.title)
                            .locktyNumericTransition(trigger: viewModel.state.currentPace)
                        Spacer()
                        Text(viewModel.state.annualEquivalent)
                            .font(LocktyTypography.callout)
                            .foregroundStyle(LocktyColors.secondaryText)
                            .locktyNumericTransition(trigger: viewModel.state.annualEquivalent)
                    }
                }

                SectionHeader(title: "Trends")
                LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: LocktySpacing.sm) {
                    ForEach(viewModel.state.trends) { trend in
                        CardView {
                            VStack(alignment: .leading, spacing: LocktySpacing.xs) {
                                Text(trend.title)
                                    .font(LocktyTypography.caption)
                                    .foregroundStyle(LocktyColors.secondaryText)
                                Text(trend.value)
                                    .font(LocktyTypography.title)
                                    .locktyNumericTransition(trigger: trend.value)
                                Text(trend.detail)
                                    .font(LocktyTypography.caption)
                                    .foregroundStyle(trend.detail.hasPrefix("-") ? LocktyColors.unproductive : LocktyColors.productive)
                                    .locktyNumericTransition(trigger: trend.detail)
                            }
                        }
                    }
                }

                SectionHeader(title: "Patterns")
                VStack(spacing: LocktySpacing.sm) {
                    ForEach(Array(viewModel.state.patterns.enumerated()), id: \.offset) { _, pattern in
                        CardView {
                            Text(pattern)
                                .font(LocktyTypography.callout)
                                .foregroundStyle(LocktyColors.secondaryText)
                        }
                    }
                }
            }
            .padding(.horizontal, LocktySpacing.md)
            .padding(.vertical, LocktySpacing.lg)
        }
        .scrollIndicators(.hidden)
        .toolbarVisibility(.hidden, for: .navigationBar)
        .task {
            await viewModel.load()
        }
    }
}
