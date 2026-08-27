import SwiftUI

struct FocusSectionPicker: View {
    @Bindable var viewModel: FocusViewModel

    var body: some View {
        Picker("Focus area", selection: $viewModel.selectedSection) {
            ForEach(FocusSection.allCases) { section in
                Text(section.title).tag(section)
            }
        }
        .pickerStyle(.segmented)
        .accessibilityLabel("Focus area")
    }
}
