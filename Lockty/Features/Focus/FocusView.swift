import SwiftUI

struct FocusView: View {
    @Bindable var viewModel: FocusViewModel
    let routinesViewModel: RoutinesViewModel
    let pausesViewModel: PausesViewModel
    let router: AppRouter

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: LocktySpacing.lg) {
                Text("Focus")
                    .font(LocktyTypography.largeTitle)
                    .foregroundStyle(LocktyColors.primaryText)

                FocusSectionPicker(viewModel: viewModel)

                switch viewModel.selectedSection {
                case .routines:
                    RoutinesView(viewModel: routinesViewModel, router: router)
                case .pauses:
                    PausesView(viewModel: pausesViewModel, router: router)
                }
            }
            .padding(.horizontal, LocktySpacing.md)
            .padding(.top, LocktySpacing.lg)
            .padding(.bottom, LocktySpacing.xl)
        }
        .scrollIndicators(.hidden)
        .locktyScreenBackground()
        .toolbarVisibility(.hidden, for: .navigationBar)
        .task {
            await routinesViewModel.load()
            await pausesViewModel.load()
        }
    }
}
