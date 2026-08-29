import SwiftUI

struct FocusSectionPicker: View {
    @ObservedObject var viewModel: FocusViewModel

    var body: some View {
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
        .labelsHidden()
        .accessibilityLabel("Focus area")
    }
}
