import SwiftUI

struct RoutineDomainsSheet: View {
    @State private var viewModel: RoutineEditorViewModel
    @Environment(\.dismiss) private var dismiss

    init(viewModel: RoutineEditorViewModel) {
        _viewModel = State(initialValue: viewModel)
    }

    var body: some View {
        @Bindable var viewModel = viewModel

        LocktyDynamicSheet {
            VStack(alignment: .leading, spacing: 0) {
                EditorTopBar(title: "Websites", onClose: { dismiss() })

                ScrollView(.vertical, showsIndicators: false) {
                    VStack(alignment: .leading, spacing: LocktySpacing.md) {
                        HStack(spacing: LocktySpacing.sm) {
                            TextField("google.com", text: $viewModel.pendingDomain)
                                .textInputAutocapitalization(.never)
                                .autocorrectionDisabled()
                                .locktyGlassInputStyle()

                            Button("Add") {
                                withAnimation(.smooth(duration: 0.24)) {
                                    viewModel.addDomain()
                                }
                            }
                            .buttonStyle(.plain)
                            .padding(.horizontal, LocktySpacing.md)
                            .frame(height: 52)
                            .safeGlass(radius: LocktyRadius.medium, interactive: true, tint: LocktyColors.primaryText)
                        }

                        if !viewModel.blockedDomains.isEmpty {
                            CardView(radius: LocktyRadius.medium, padding: LocktySpacing.md) {
                                DomainChipFlow(domains: viewModel.blockedDomains) { domain in
                                    withAnimation(.smooth(duration: 0.24)) {
                                        viewModel.removeDomain(domain)
                                    }
                                }
                            }
                        }
                    }
                    .padding(.horizontal, LocktySpacing.md)
                    .padding(.top, LocktySpacing.sm)
                    .padding(.bottom, LocktySpacing.md)
                }
            }
        }
    }
}
