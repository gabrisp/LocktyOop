import SwiftUI

struct RoutineDomainsSheet: View {
    @State private var viewModel: RoutineEditorViewModel
    @Environment(\.dismiss) private var dismiss

    init(viewModel: RoutineEditorViewModel) {
        _viewModel = State(initialValue: viewModel)
    }

    var body: some View {
        @Bindable var viewModel = viewModel

        VStack(alignment: .leading, spacing: 0) {
            EditorTopBar(
                title: "Websites",
                confirmTitle: "Done",
                onClose: { dismiss() },
                onConfirm: { dismiss() }
            )

            ScrollView(.vertical, showsIndicators: false) {
                VStack(alignment: .leading, spacing: LocktySpacing.md) {
                    CardView(radius: LocktyRadius.medium, padding: LocktySpacing.md) {
                        VStack(alignment: .leading, spacing: LocktySpacing.md) {
                            Text("Add a website domain to block while this routine runs.")
                                .font(LocktyTypography.callout)
                                .foregroundStyle(LocktyColors.secondaryText)

                            HStack(spacing: LocktySpacing.sm) {
                                TextField("google.com", text: $viewModel.pendingDomain)
                                    .textInputAutocapitalization(.never)
                                    .autocorrectionDisabled()
                                    .font(LocktyTypography.body)
                                    .foregroundStyle(LocktyColors.primaryText)

                                Button("Add") {
                                    viewModel.addDomain()
                                }
                                .buttonStyle(.borderedProminent)
                            }
                        }
                    }

                    if !viewModel.blockedDomains.isEmpty {
                        CardView(radius: LocktyRadius.medium, padding: LocktySpacing.md) {
                            VStack(alignment: .leading, spacing: LocktySpacing.sm) {
                                Text("Websites (\(viewModel.blockedDomains.count))")
                                    .font(LocktyTypography.headline)
                                    .foregroundStyle(LocktyColors.primaryText)

                                DomainChipFlow(domains: viewModel.blockedDomains) { domain in
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
        .locktyScreenBackground()
        .toolbarVisibility(.hidden, for: .navigationBar)
    }
}
