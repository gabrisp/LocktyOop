import SwiftUI

struct LocktyPicker<Option: Hashable & Identifiable, Label: View>: View {
    let title: String
    let options: [Option]
    @Binding var selection: Option
    let label: (Option) -> Label

    var body: some View {
        Picker(title, selection: $selection) {
            ForEach(options) { option in
                label(option).tag(option)
            }
        }
        .pickerStyle(.segmented)
    }
}
