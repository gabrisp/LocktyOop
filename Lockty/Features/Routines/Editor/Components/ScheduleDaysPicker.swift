import SwiftUI

struct ScheduleDaysPicker: View {
    @Binding var selectedWeekdays: Set<Weekday>

    private let orderedWeekdays: [Weekday] = [.monday, .tuesday, .wednesday, .thursday, .friday, .saturday, .sunday]

    var body: some View {
        HStack(spacing: LocktySpacing.sm) {
            ForEach(orderedWeekdays) { weekday in
                let isSelected = selectedWeekdays.contains(weekday)
                Button {
                    if isSelected {
                        selectedWeekdays.remove(weekday)
                    } else {
                        selectedWeekdays.insert(weekday)
                    }
                } label: {
                    Text(weekday.shortLabel)
                        .font(LocktyTypography.caption)
                        .foregroundStyle(isSelected ? Color.black : LocktyColors.primaryText)
                        .frame(width: 36, height: 36)
                        .background(
                            isSelected ? AnyShapeStyle(Color.accentColor) : AnyShapeStyle(LocktyColors.elevatedBackground),
                            in: Circle()
                        )
                }
                .buttonStyle(.plain)
                .tappable()
            }
        }
    }
}

private extension Weekday {
    var shortLabel: String {
        switch self {
        case .sunday: "S"
        case .monday: "M"
        case .tuesday: "T"
        case .wednesday: "W"
        case .thursday: "T"
        case .friday: "F"
        case .saturday: "S"
        }
    }
}
