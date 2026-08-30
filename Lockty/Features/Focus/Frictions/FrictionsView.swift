import SwiftUI

struct FrictionsView: View {
    @ObservedObject var viewModel: FrictionsViewModel
    let router: AppRouter
    var showsAddTile = true

    private let columns = [
        GridItem(.flexible(), spacing: RoutineGridMetrics.spacing),
        GridItem(.flexible(), spacing: RoutineGridMetrics.spacing)
    ]

    var body: some View {
        VStack(alignment: .leading, spacing: LocktySpacing.lg) {
            LazyVGrid(columns: columns, spacing: RoutineGridMetrics.spacing) {
                ForEach(viewModel.frictions) { friction in
                    FrictionCard(friction: friction) {
                        router.presentSheet(.frictionEditor(FrictionEditorRoute(frictionID: friction.id)))
                    }
                }

                if showsAddTile {
                    addFrictionTile
                }
            }
        }
        .task {
            await viewModel.load()
        }
        .onChange(of: router.sheet) { _, newValue in
            guard newValue == nil else { return }
            Task { await viewModel.load() }
        }
        .alert(
            "Friction action failed",
            isPresented: Binding(
                get: { viewModel.errorMessage != nil },
                set: { if !$0 { viewModel.errorMessage = nil } }
            )
        ) {
            Button("OK", role: .cancel) {
                viewModel.errorMessage = nil
            }
        } message: {
            Text(viewModel.errorMessage ?? "")
        }
    }

    private var addFrictionTile: some View {
        Button {
            router.presentSheet(.frictionEditor(FrictionEditorRoute(frictionID: nil)))
        } label: {
            CardView(interactive: true, height: RoutineGridMetrics.tileHeight) {
                VStack(alignment: .leading, spacing: LocktySpacing.md) {
                    Image(systemName: "plus")
                        .font(.system(size: 16, weight: .light))
                        .foregroundStyle(LocktyColors.primaryText)
                        .frame(width: 24, height: 24)

                    Spacer(minLength: 0)

                    Text("Add Friction")
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

private struct FrictionCard: View {
    let friction: Friction
    let onOpen: () -> Void

    var body: some View {
        Button(action: onOpen) {
            CardView(radius: RoutineGridMetrics.tileRadius, interactive: true, height: RoutineGridMetrics.tileHeight) {
                VStack(alignment: .leading, spacing: LocktySpacing.sm) {
                    Image(systemName: friction.icon ?? "slider.horizontal.3")
                        .font(.system(size: 16, weight: .light))
                        .foregroundStyle(LocktyColors.primaryText)
                        .frame(width: 24, height: 24)

                    Spacer(minLength: 0)

                    Text(friction.summary)
                        .font(LocktyTypography.caption)
                        .foregroundStyle(LocktyColors.secondaryText)
                        .lineLimit(2)

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
