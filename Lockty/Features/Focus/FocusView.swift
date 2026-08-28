import SwiftUI

struct FocusView: View {
    @Bindable var viewModel: FocusViewModel
    let routinesViewModel: RoutinesViewModel
    let pausesViewModel: PausesViewModel
    let router: AppRouter

    var body: some View {
        VStack(alignment: .leading, spacing: LocktySpacing.lg) {
            Text("Focus")
                .font(LocktyTypography.largeTitle)
                .foregroundStyle(LocktyColors.primaryText)
                .padding(.horizontal, LocktySpacing.md)

            FocusSectionPicker(viewModel: viewModel)
                .padding(.horizontal, LocktySpacing.md)

            ScrollView(.horizontal) {
                LazyHStack(spacing: 0) {
                    ScrollView(.vertical) {
                        RoutinesView(viewModel: routinesViewModel, router: router)
                            .padding(.horizontal, LocktySpacing.md)
                            .padding(.bottom, LocktySpacing.xl)
                    }
                    .scrollIndicators(.hidden)
                    .containerRelativeFrame(.horizontal)
                    .id(FocusSection.routines)

                    ScrollView(.vertical) {
                        PausesView(viewModel: pausesViewModel, router: router)
                            .padding(.horizontal, LocktySpacing.md)
                            .padding(.bottom, LocktySpacing.xl)
                    }
                    .scrollIndicators(.hidden)
                    .containerRelativeFrame(.horizontal)
                    .id(FocusSection.pauses)
                }
                .scrollTargetLayout()
            }
            .scrollTargetBehavior(.paging)
            .scrollPosition(
                id: Binding(
                    get: { viewModel.selectedSection },
                    set: { newValue in
                        if let newValue {
                            viewModel.selectedSection = newValue
                        }
                    }
                )
            )
            .scrollIndicators(.hidden)
        }
        .padding(.top, LocktySpacing.lg)
        .locktyScreenBackground()
        .toolbarVisibility(.hidden, for: .navigationBar)
        .task {
            await routinesViewModel.load()
            await pausesViewModel.load()
        }
    }
}
