import SwiftUI

struct ActiveRoutineChecklistCard: View {
    let state: ActiveRoutineChecklistState
    let onToggle: (ActiveRoutineChecklistItemState) -> Void

    var body: some View {
        CardView(padding: 0, interactive: true) {
            VStack(spacing: 0) {
                ForEach(Array(state.items.enumerated()), id: \.element.id) { index, item in
                    Button {
                        onToggle(item)
                    } label: {
                        HStack(spacing: 18) {
                            Image(systemName: item.isCompleted ? "checkmark.circle" : "circle")
                                .font(.system(size: 40, weight: .regular))
                                .foregroundStyle(LocktyColors.primaryText)

                            Text(item.title)
                                .font(.system(size: 30, weight: .light, design: .default))
                                .foregroundStyle(LocktyColors.primaryText)
                                .strikethrough(item.isCompleted, color: LocktyColors.primaryText)
                                .lineLimit(1)
                                .minimumScaleFactor(0.72)
                                .frame(maxWidth: .infinity, alignment: .leading)
                        }
                        .padding(.horizontal, 22)
                        .padding(.vertical, 16)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    .tappable()

                    if index < state.items.count - 1 {
                        Divider()
                            .padding(.leading, 80)
                    }
                }
            }
        }
    }
}
