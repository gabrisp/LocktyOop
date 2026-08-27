import SwiftUI

struct RoutineIconPickerSheet: View {
    @Binding var selectedIcon: String
    @Environment(\.dismiss) private var dismiss

    private let columns = Array(repeating: GridItem(.flexible(), spacing: LocktySpacing.md), count: 4)

    var body: some View {
        NavigationStack {
            ScrollView {
                LazyVGrid(columns: columns, spacing: LocktySpacing.md) {
                    ForEach(RoutineIconColorCatalog.icons, id: \.self) { iconName in
                        let isSelected = iconName == selectedIcon
                        Button {
                            selectedIcon = iconName
                            dismiss()
                        } label: {
                            Image(systemName: iconName)
                                .font(.system(size: 22, weight: .semibold))
                                .foregroundStyle(isSelected ? Color.black : LocktyColors.primaryText)
                                .frame(width: 56, height: 56)
                                .background(
                                    isSelected ? AnyShapeStyle(Color.accentColor) : AnyShapeStyle(LocktyColors.elevatedBackground),
                                    in: Circle()
                                )
                        }
                        .buttonStyle(.plain)
                        .tappable()
                    }
                }
                .padding(LocktySpacing.lg)
            }
            .locktyScreenBackground()
            .navigationTitle("Icon")
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
