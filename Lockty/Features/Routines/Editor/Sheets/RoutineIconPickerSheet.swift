import SwiftUI

struct RoutineIconPickerSheet: View {
    @Binding var selectedIcon: String
    @Environment(\.dismiss) private var dismiss

    private let columns = Array(repeating: GridItem(.flexible()), count: 4)

    var body: some View {
        LocktyDynamicSheet {
            VStack(alignment: .leading, spacing: 0) {
                EditorTopBar(
                    title: "Icon",
                    confirmTitle: "Done",
                    onClose: { dismiss() },
                    onConfirm: { dismiss() }
                )

                ScrollView {
                    LazyVGrid(columns: columns, spacing: LocktySpacing.md) {
                        ForEach(RoutineIconCatalog.icons, id: \.self) { iconName in
                            let isSelected = iconName == selectedIcon
                            Button {
                                selectedIcon = iconName
                                dismiss()
                            } label: {
                                Image(systemName: iconName)
                                    .font(.system(size: 22, weight: .semibold))
                                    .foregroundStyle(isSelected ? Color.black : LocktyColors.primaryText)
                                    .frame(width: 56, height: 56)
                                    .safeGlass(
                                        radius: 28,
                                        interactive: true,
                                        tint: isSelected ? .accentColor : nil
                                    )
                                    .clipShape(Circle())
                            }
                            .buttonStyle(.plain)
                            .tappable()
                        }
                    }
                    .padding(LocktySpacing.lg)
                }
            }
            .locktyScreenBackground()
            .toolbarVisibility(.hidden, for: .navigationBar)
        }
    }
}
