import FamilyControls
import OSLog
import SwiftUI

private let appPickerLogger = Logger(subsystem: "com.gabrisp.Lockty", category: "selection")

@MainActor
@Observable
final class AppPickerViewModel {
    var selection: FamilyActivitySelection
    private let selectionStore: ScreenTimeSelectionStore
    let scope: ScreenTimeSelectionScope

    init(selectionStore: ScreenTimeSelectionStore, scope: ScreenTimeSelectionScope) {
        self.selectionStore = selectionStore
        self.scope = scope
        selection = (try? selectionStore.load(scope: scope)) ?? FamilyActivitySelection()
        normalizeSelection(previousSelection: FamilyActivitySelection())
    }

    func save() throws {
        normalizeSelection(previousSelection: selection)
        try selectionStore.save(selection, scope: scope)
        appPickerLogger.notice("Picker save scope=\(self.scope.id, privacy: .public) apps=\(self.selection.applicationTokens.count) categories=\(self.selection.categoryTokens.count) domains=\(self.selection.webDomainTokens.count)")
    }

    var navigationTitle: String {
        switch scope {
        case .library:
            "Choose Apps and Websites"
        case .routine:
            "Choose Apps"
        case .pause:
            "Choose App"
        }
    }

    var showsExplicitSaveAction: Bool {
        !isSingleApplicationScope
    }

    var helperText: String? {
        switch scope {
        case .pause:
            return "Pauses support exactly one application."
        case .routine:
            return "Domains are configured separately in the routine editor."
        case .library:
            return nil
        }
    }

    var descriptionText: String {
        switch scope {
        case .library:
            return "Choose the apps and websites Lockty can use across routines, pauses and reports."
        case .routine:
            return "Choose the applications this routine will restrict when it starts."
        case .pause:
            return "Choose the one application that will trigger this Pause flow."
        }
    }

    func selectionDidChange(from previousSelection: FamilyActivitySelection) {
        normalizeSelection(previousSelection: previousSelection)
    }

    func persistCurrentSelection() throws {
        try save()
    }

    func shouldAutoCommitSelection(after previousSelection: FamilyActivitySelection) -> Bool {
        guard isSingleApplicationScope else { return false }
        let newApplications = selection.applicationTokens
        let previousApplications = previousSelection.applicationTokens
        return newApplications.count == 1 && newApplications != previousApplications
    }

    private var isSingleApplicationScope: Bool {
        if case .pause = scope {
            return true
        }
        return false
    }

    private func normalizeSelection(previousSelection: FamilyActivitySelection) {
        let appsOnlyScope: Bool
        switch scope {
        case .library:
            appsOnlyScope = false
        case .routine, .pause:
            appsOnlyScope = true
        }

        if appsOnlyScope {
            if !selection.categoryTokens.isEmpty {
                selection.categoryTokens = []
            }

            if !selection.webDomainTokens.isEmpty {
                selection.webDomainTokens = []
            }
        }

        guard isSingleApplicationScope else { return }

        if selection.applicationTokens.count > 1 {
            let addedApplication = selection.applicationTokens.subtracting(previousSelection.applicationTokens).first
            let keptApplication = addedApplication
                ?? previousSelection.applicationTokens.first(where: { selection.applicationTokens.contains($0) })
                ?? selection.applicationTokens.first

            selection.applicationTokens = keptApplication.map { [$0] } ?? []
        }
    }
}

struct AppPickerSheet: View {
    @Bindable var viewModel: AppPickerViewModel
    @Environment(\.dismiss) private var dismiss
    @State private var errorMessage: String?

    var body: some View {
        NavigationStack {
            VStack(alignment: .leading, spacing: LocktySpacing.md) {
                EditorTopBar(
                    title: viewModel.navigationTitle,
                    confirmTitle: "Done",
                    onClose: { dismiss() },
                    onConfirm: {
                        do {
                            try viewModel.persistCurrentSelection()
                            dismiss()
                        } catch {
                            errorMessage = error.localizedDescription
                        }
                    }
                )

                CardView(radius: LocktyRadius.medium, padding: LocktySpacing.md) {
                    VStack(alignment: .leading, spacing: LocktySpacing.xs) {
                        Text(viewModel.descriptionText)
                            .font(LocktyTypography.callout)
                            .foregroundStyle(LocktyColors.secondaryText)

                        if let helperText = viewModel.helperText {
                            Text(helperText)
                                .font(LocktyTypography.caption)
                                .foregroundStyle(LocktyColors.tertiaryText)
                        }
                    }
                }

                FamilyActivityPicker(selection: $viewModel.selection)
                    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
            }
            .padding(.horizontal, LocktySpacing.md)
            .padding(.bottom, LocktySpacing.md)
            .locktyScreenBackground()
            .toolbarVisibility(.hidden, for: .navigationBar)
            .alert("Could not save selection", isPresented: Binding(get: { errorMessage != nil }, set: { if !$0 { errorMessage = nil } })) {
                Button("OK", role: .cancel) { errorMessage = nil }
            } message: {
                Text(errorMessage ?? "")
            }
            .onChange(of: viewModel.selection) { oldValue, newValue in
                guard oldValue != newValue else { return }
                viewModel.selectionDidChange(from: oldValue)
                do {
                    try viewModel.persistCurrentSelection()
                } catch {
                    errorMessage = error.localizedDescription
                    return
                }
                guard viewModel.shouldAutoCommitSelection(after: oldValue) else { return }
                dismiss()
            }
        }
    }
}
