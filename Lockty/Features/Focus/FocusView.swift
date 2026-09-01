import SwiftUI

struct FocusView: View {
    @ObservedObject var viewModel: FocusViewModel
    let rulesViewModel: RulesViewModel
    let frictionsViewModel: FrictionsViewModel
    @ObservedObject var appsViewModel: AppsLibraryViewModel
    @ObservedObject var router: AppRouter
    let frictionRepository: FrictionRepository

    private var gutter: CGFloat { LocktySpacing.lg }
    private var tileWidth: CGFloat { RoutineGridMetrics.tileWidth }
    private var appTileWidth: CGFloat { 110 }
    private var appFolderShape: RoundedRectangle {
        RoundedRectangle(cornerRadius: 28, style: .continuous)
    }

    var body: some View {
        ScrollView(.vertical, showsIndicators: false) {
            VStack(alignment: .leading, spacing: LocktySpacing.xl) {
                section(title: "Rules") {
                    router.push(.rulesList)
                } content: {
                    rulesRow
                }

                section(title: "Frictions") {
                    router.push(.frictionsList)
                } content: {
                    frictionsRow
                }

                section(title: "Apps") {
                    router.push(.appsList)
                } content: {
                    appsRow
                }
            }
            .padding(.horizontal, gutter)
            .padding(.vertical, LocktySpacing.lg)
        }
        .navigationTitle("Focus")
        .navigationBarTitleDisplayMode(.large)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Button {
                    router.presentSheet(.focusCreationChoice(FocusCreationChoiceRoute()))
                } label: {
                    Image(systemName: "plus")
                }
            }
        }
        .task {
            await frictionRepository.seedDefaultFrictionIfNeeded()
            await rulesViewModel.load()
            await frictionsViewModel.load()
            await appsViewModel.load()
        }
        .onChange(of: router.sheet) { _, newValue in
            guard newValue == nil else { return }
            Task {
                await rulesViewModel.load()
                await frictionsViewModel.load()
                await appsViewModel.load()
            }
        }
    }

    @ViewBuilder
    private func section<Content: View>(
        title: String,
        onOpen: @escaping () -> Void,
        @ViewBuilder content: () -> Content
    ) -> some View {
        VStack(alignment: .leading, spacing: LocktySpacing.md) {
            LocktySectionTitle(title, onOpen: onOpen)
            content()
        }
    }

    private var rulesRow: some View {
        horizontalRow {
            addTile(title: "New Rule") {
                router.presentSheet(.ruleEditor(RuleEditorRoute(ruleID: nil)))
            }

            ForEach(rulesViewModel.rules) { rule in
                Group {
                    if let routine = rule.routineBridge {
                        RoutineCard(
                            routine: routine,
                            isActive: rulesViewModel.activeScheduleRuleIDs().contains(rule.id),
                            applicationTokens: rulesViewModel.tokens(for: rule.id)
                        ) {
                            router.presentSheet(.routineEditor(RoutineEditorRoute(routineID: rule.id)))
                        }
                    } else {
                        RuleCard(rule: rule, applicationTokens: rulesViewModel.tokens(for: rule.id)) {
                            router.presentSheet(.ruleEditor(RuleEditorRoute(ruleID: rule.id)))
                        }
                    }
                }
                .frame(width: tileWidth)
                .transition(.blurReplace.combined(with: .scale(0.88)).combined(with: .opacity))
            }
        }
        .animation(.smooth(duration: 0.34), value: rulesViewModel.rules.map(\.id))
    }

    private var frictionsRow: some View {
        horizontalRow {
            addTile(title: "New Friction") {
                router.presentSheet(.frictionEditor(FrictionEditorRoute(frictionID: nil)))
            }

            ForEach(frictionsViewModel.frictions) { friction in
                FrictionFocusCard(friction: friction) {
                    router.presentSheet(.frictionEditor(FrictionEditorRoute(frictionID: friction.id)))
                }
                .frame(width: tileWidth)
                .transition(.blurReplace.combined(with: .scale(0.88)).combined(with: .opacity))
            }
        }
        .animation(.smooth(duration: 0.34), value: frictionsViewModel.frictions.map(\.id))
    }

    private var appsRow: some View {
        horizontalRow {
            Button {
                router.push(.distractingGroup)
            } label: {
                AppFolderCard(
                    title: "Distrayendo",
                    subtitle: folderCountText(appsViewModel.distractingTokens.count),
                    tokens: appsViewModel.distractingTokens
                )
                .frame(width: appTileWidth)
            }
            .buttonStyle(.locktyInteractive(shape: appFolderShape))

            ForEach(appsViewModel.appGroups) { group in
                Button {
                    router.push(.appGroupEditor(AppGroupEditorRoute(appGroupID: group.id)))
                } label: {
                    AppFolderCard(
                        title: group.name,
                        subtitle: folderCountText(appsViewModel.tokens(for: group.id).count),
                        tokens: appsViewModel.tokens(for: group.id)
                    )
                    .frame(width: appTileWidth)
                }
                .buttonStyle(.locktyInteractive(shape: appFolderShape))
            }

            Button {
                router.push(.appGroupEditor(AppGroupEditorRoute(appGroupID: nil)))
            } label: {
                AddAppFolderCard()
                    .frame(width: appTileWidth)
            }
            .buttonStyle(.locktyInteractive(shape: appFolderShape))
        }
        .animation(.smooth(duration: 0.34), value: appsViewModel.appGroups.map(\.id))
        .animation(.smooth(duration: 0.34), value: appsViewModel.distractingTokens.count)
    }

    private func folderCountText(_ count: Int) -> String {
        count == 1 ? "1 elemento" : "\(count) elementos"
    }

    @ViewBuilder
    private func horizontalRow<Content: View>(@ViewBuilder content: () -> Content) -> some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: RoutineGridMetrics.spacing) {
                content()
            }
            .padding(.horizontal, gutter)
        }
        .scrollIndicators(.hidden)
        .scrollClipDisabled()
        .padding(.horizontal, -gutter)
    }

    private func addTile(title: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            CardView(radius: RoutineGridMetrics.tileRadius, interactive: true, height: RoutineGridMetrics.tileHeight) {
                VStack(spacing: LocktySpacing.sm) {
                    Spacer(minLength: 0)

                    Image(systemName: "plus")
                        .font(.system(size: 20, weight: .regular))
                        .foregroundStyle(Color(uiColor: .systemBackground))
                        .frame(width: 44, height: 44)
                        .background(Circle().fill(LocktyColors.primaryText))

                    Text(title)
                        .font(.system(.subheadline, design: .default, weight: .semibold))
                        .foregroundStyle(LocktyColors.primaryText)
                        .lineLimit(1)

                    Spacer(minLength: 0)
                }
                .frame(maxWidth: .infinity)
            }
        }
        .buttonStyle(.locktyInteractive)
        .tappable()
        .frame(width: tileWidth)
    }
}

private struct FrictionFocusCard: View {
    let friction: Friction
    let onOpen: () -> Void

    var body: some View {
        Button(action: onOpen) {
            CardView(
                radius: RoutineGridMetrics.tileRadius,
                interactive: true,
                height: RoutineGridMetrics.tileHeight
            ) {
                VStack(alignment: .leading, spacing: LocktySpacing.sm) {
                    Image(systemName: friction.icon ?? "slider.horizontal.3")
                        .font(.system(size: 16, weight: .light))
                        .foregroundStyle(LocktyColors.primaryText)
                        .frame(width: 24, height: 24)

                    Spacer(minLength: 0)

                    Text(friction.summary)
                        .font(LocktyTypography.caption)
                        .foregroundStyle(LocktyColors.secondaryText)
                        .lineLimit(1)

                    Text(friction.name)
                        .font(.system(.subheadline, design: .default, weight: .bold))
                        .foregroundStyle(LocktyColors.primaryText)
                        .lineLimit(2)
                }
            }
        }
        .buttonStyle(.locktyInteractive)
        .tappable()
    }
}
