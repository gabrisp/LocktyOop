import SwiftUI

struct ScheduleDaysPicker: View {
    @Binding var selectedWeekdays: Set<Weekday>

    private let orderedWeekdays: [Weekday] = [.monday, .tuesday, .wednesday, .thursday, .friday, .saturday, .sunday]

    var body: some View {
        HStack(spacing: 0) {
            ForEach(orderedWeekdays) { weekday in
                let isSelected = selectedWeekdays.contains(weekday)
                Button {
                    withAnimation(.snappy(duration: 0.2)) {
                        if isSelected {
                            selectedWeekdays.remove(weekday)
                        } else {
                            selectedWeekdays.insert(weekday)
                        }
                    }
                } label: {
                    Text(weekday.shortLabel)
                        .font(LocktyTypography.callout)
                        .foregroundStyle(isSelected ? Color(uiColor: .systemBackground) : LocktyColors.secondaryText)
                        .frame(width: 50, height: 50)
                        .background(
                            isSelected ? AnyShapeStyle(LocktyColors.primaryText) : AnyShapeStyle(LocktyColors.elevatedBackground),
                            in: RoundedRectangle(cornerRadius: LocktyRadius.medium, style: .continuous)
                        )
                }
                .buttonStyle(.plain)
                .tappable()
                .frame(maxWidth: .infinity)
            }
        }
    }
}

// The English initials this used to carry now live on Weekday itself, in Spanish, since
// that is what the screens using them are written in.
