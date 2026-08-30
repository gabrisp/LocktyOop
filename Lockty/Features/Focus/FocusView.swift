import SwiftUI

struct FocusView: View {
    @ObservedObject var viewModel: FocusViewModel
    let routinesViewModel: RoutinesViewModel
    let frictionsViewModel: FrictionsViewModel
    @ObservedObject var router: AppRouter
    let frictionRepository: FrictionRepository

    private var gutter: CGFloat { LocktySpacing.lg }
    private var tileWidth: CGFloat { RoutineGridMetrics.tileWidth }

    var body: some View {
        ScrollView(.vertical, showsIndicators: false) {
            VStack(alignment: .leading, spacing: LocktySpacing.xl) {
                section(title: "Routines") {
                    router.push(.routinesList)
                } content: {
                    routinesRow
                }

                section(title: "Frictions") {
                    router.push(.frictionsList)
                } content: {
                    frictionsRow
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
            await routinesViewModel.load()
            await frictionsViewModel.load()
        }
        .onChange(of: router.sheet) { _, newValue in
            guard newValue == nil else { return }
            Task {
                await routinesViewModel.load()
                await frictionsViewModel.load()
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

    private var routinesRow: some View {
        horizontalRow {
            addTile(title: "New Routine") {
                router.presentSheet(.routineEditor(RoutineEditorRoute(routineID: nil)))
            }

            ForEach(routinesViewModel.routines) { routine in
                RoutineCard(
                    routine: routine,
                    isActive: routinesViewModel.activeRoutineID() == routine.id,
                    applicationTokens: routinesViewModel.tokens(for: routine.id),
                    onOpen: {
                        router.presentSheet(.routineEditor(RoutineEditorRoute(routineID: routine.id)))
                    }
                )
                .frame(width: tileWidth)
                .transition(.blurReplace.combined(with: .scale(0.88)).combined(with: .opacity))
            }
        }
        .animation(.smooth(duration: 0.34), value: routinesViewModel.routines.map(\.id))
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
