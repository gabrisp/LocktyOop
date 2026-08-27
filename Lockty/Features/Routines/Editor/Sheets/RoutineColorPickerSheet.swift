import SwiftUI

struct RoutineColorPickerSheet: View {
    @Binding var selectedColorHex: String
    @Environment(\.dismiss) private var dismiss

    private let columns = Array(repeating: GridItem(.flexible(), spacing: LocktySpacing.md), count: 4)

    var body: some View {
        NavigationStack {
            ScrollView {
                LazyVGrid(columns: columns, spacing: LocktySpacing.md) {
                    ForEach(RoutineIconColorCatalog.colors, id: \.self) { hex in
                        let isSelected = hex.caseInsensitiveCompare(selectedColorHex) == .orderedSame
                        Button {
                            selectedColorHex = hex
                            dismiss()
                        } label: {
                            Circle()
                                .fill(Color(hex: hex))
                                .frame(width: 56, height: 56)
                                .overlay {
                                    Circle().stroke(Color.white, lineWidth: isSelected ? 3 : 0)
                                }
                        }
                        .buttonStyle(.plain)
                        .tappable()
                    }
                }
                .padding(LocktySpacing.lg)
            }
            .locktyScreenBackground()
            .navigationTitle("Color")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    IconButton(systemImage: "xmark", accessibilityLabel: "Close") { dismiss() }
                }
            }
        }
        .presentationDetents([.medium, .large])
    }
}
