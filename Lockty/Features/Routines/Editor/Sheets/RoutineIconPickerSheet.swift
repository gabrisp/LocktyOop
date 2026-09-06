import SwiftUI

struct RoutineIconPickerSheet: View {
    @Binding var selectedIcon: String
    @Environment(\.dismiss) private var dismiss

    private let columns = Array(repeating: GridItem(.flexible()), count: 4)

    /// Three rows, scrolling sideways.
    ///
    /// A vertical grid of a hundred glyphs is a wall you have to read line by line; a
    /// strip you flick through is a shelf you scan. The padding is on the contents rather
    /// than on the scroll view, so the first and last icons sit inside the popover's edge
    /// while the row itself still runs from edge to edge.
    private let rows = Array(repeating: GridItem(.fixed(46), spacing: LocktySpacing.md), count: 3)

    var body: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            LazyHGrid(rows: rows, spacing: LocktySpacing.md) {
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
                            .background {
                                Circle().fill(isSelected ? LocktyColors.primaryText : LocktyColors.ink(0.06))
                            }
                            .contentShape(Circle())
                    }
                    .buttonStyle(.locktyInteractive(shape: Circle()))
                    .tappable()
                }
            }
            .padding(.horizontal, LocktySpacing.md)
            .padding(.vertical, LocktySpacing.sm)
        }
        .scrollClipDisabled()
        .frame(width: 300, height: 170)
    }
}
