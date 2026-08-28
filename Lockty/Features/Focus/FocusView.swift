import SwiftUI

struct FocusView: View {
    @Bindable var viewModel: FocusViewModel
    let routinesViewModel: RoutinesViewModel
    let pausesViewModel: PausesViewModel
    let router: AppRouter

    var body: some View {
            ScrollView(.horizontal, showsIndicators: false) {
                LazyHStack(spacing: 0) {
                    ScrollView(.vertical, showsIndicators: false) {
                        RoutinesView(viewModel: routinesViewModel, router: router)
                            .padding(.horizontal, LocktySpacing.md)
                            .padding(.bottom, LocktySpacing.xl)
                            .padding(.top, LocktySpacing.md)
                    }
                    .scrollIndicators(.hidden)
                    .containerRelativeFrame(.horizontal)
                    .id(FocusSection.routines)

                    ScrollView(.vertical, showsIndicators: false) {
                        PausesView(viewModel: pausesViewModel, router: router)
                            .padding(.horizontal, LocktySpacing.md)
                            .padding(.bottom, LocktySpacing.xl)
                            .padding(.top, LocktySpacing.md)
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
            .toolbar{
                ToolbarItem(placement: .principal) {
                    Picker("", selection: Binding(
                        get: { viewModel.selectedSection },
                        set: { newValue in
                            withAnimation(.snappy) {
                                viewModel.selectedSection = newValue
                            }
                        }
                    )) {
                        ForEach(FocusSection.allCases) { section in
                            Text(section.title).tag(section)
                        }
                    }
                    .pickerStyle(.segmented)
                }
            }
            .task {
                await routinesViewModel.load()
                await pausesViewModel.load()
            }
    }
}
