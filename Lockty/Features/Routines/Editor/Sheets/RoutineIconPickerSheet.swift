import SwiftUI

struct RoutineIconPickerSheet: View {
    @Binding var selectedIcon: String
    @Environment(\.dismiss) private var dismiss

    private let columns = Array(repeating: GridItem(.flexible()), count: 4)

    var body: some View {
        ScrollView(showsIndicators: false) {
            LazyVGrid(columns: columns, spacing: LocktySpacing.md) {
                ForEach(RoutineIconCatalog.icons, id: \.self) { iconName in
                    let isSelected = iconName == selectedIcon
                    Button {
                        selectedIcon = iconName
                        dismiss()
                    } label: {
                        Image(systemName: iconName)
                            .font(.system(size: 18, weight: .medium))
                            .foregroundStyle(isSelected ? Color(uiColor: .systemBackground) : LocktyColors.primaryText)
                            .frame(width: 46, height: 46)
                            .safeGlass(
                                radius: 23,
                                interactive: true,
                                tint: isSelected ? LocktyColors.primaryText : nil
                            )
                            .clipShape(Circle())
                    }
                    .buttonStyle(.locktyInteractive(shape: Circle()))
                    .tappable()
                }
            }
            .padding(LocktySpacing.md)
        }
        .frame(width: 280, height: 320)
    }
}
