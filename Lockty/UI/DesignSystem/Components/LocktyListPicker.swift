import FamilyControls
import ManagedSettings
import SwiftUI

/// One row of a `LocktyListPicker`.
///
/// An app row carries its token and draws Apple's own icon and name from it; anything
/// that isn't an app (an "all apps" row, say) falls back to a symbol and a title.
struct LocktyPickerOption: Identifiable, Hashable {
    let id: String
    var token: ApplicationToken?
    var systemImage: String?
    var title: String

    init(id: String, token: ApplicationToken, title: String? = nil) {
        self.id = id
        self.token = token
        self.systemImage = nil
        self.title = title ?? ""
    }

    init(id: String, systemImage: String, title: String) {
        self.id = id
        self.token = nil
        self.systemImage = systemImage
        self.title = title
    }
}

/// A plain list of choices with the selected one held in a glass capsule.
///
/// Deliberately not a Picker: the selection highlight, the row height and the icon
/// treatment all have to match the wheel picker next to it in the same flow.
struct LocktyListPicker: View {
    let options: [LocktyPickerOption]
    @Binding var selection: String?

    var body: some View {
        VStack(spacing: 2) {
            ForEach(options) { option in
                Button {
                    withAnimation(.smooth(duration: 0.24)) {
                        selection = option.id
                    }
                } label: {
                    row(option)
                }
                .buttonStyle(.plain)
                .tappable()
            }
        }
        .sensoryFeedback(.selection, trigger: selection)
    }

    private func row(_ option: LocktyPickerOption) -> some View {
        let isSelected = selection == option.id

        return HStack(spacing: LocktySpacing.lg) {
            icon(option)
                .frame(width: 46, height: 46)

            if let token = option.token {
                // The token is the only thing carrying the app's real name.
                Label(token)
                    .labelStyle(.titleOnly)
                    .font(.system(.title3, design: .default, weight: .regular))
                    .foregroundStyle(LocktyColors.primaryText)
                    .lineLimit(1)
            } else {
                Text(option.title)
                    .font(.system(.title3, design: .default, weight: .regular))
                    .foregroundStyle(LocktyColors.primaryText)
                    .lineLimit(1)
            }

            Spacer(minLength: 0)
        }
        .padding(.horizontal, LocktySpacing.md)
        .padding(.vertical, LocktySpacing.sm)
        .background {
            if isSelected {
                Capsule(style: .continuous)
                    .fill(.ultraThinMaterial)
            }
        }
        .contentShape(Capsule(style: .continuous))
    }

    @ViewBuilder
    private func icon(_ option: LocktyPickerOption) -> some View {
        if let token = option.token {
            Label(token)
                .labelStyle(.iconOnly)
                .id(token)
        } else if let systemImage = option.systemImage {
            Image(systemName: systemImage)
                .font(.system(size: 20, weight: .regular))
                .foregroundStyle(LocktyColors.primaryText)
                .frame(width: 44, height: 44)
                .background(
                    RoundedRectangle(cornerRadius: 11, style: .continuous)
                        .fill(LocktyColors.elevatedBackground)
                )
        }
    }
}

/// The wheel of whole minutes, held in the same glass capsule as the list picker so the
/// two steps of a flow look like one control changing its mind.
struct LocktyMinutesPicker: View {
    let range: ClosedRange<Int>
    @Binding var minutes: Int

    private let rowHeight: CGFloat = 62

    var body: some View {
        ScrollView(.vertical, showsIndicators: false) {
            LazyVStack(spacing: 0) {
                ForEach(Array(range), id: \.self) { value in
                    Text(value == 1 ? "1 minuto" : "\(value) minutos")
                        .font(.system(.title3, design: .default, weight: value == minutes ? .semibold : .regular))
                        .foregroundStyle(LocktyColors.primaryText)
                        .frame(maxWidth: .infinity)
                        .frame(height: rowHeight)
                        .background {
                            if value == minutes {
                                Capsule(style: .continuous)
                                    .fill(.ultraThinMaterial)
                            }
                        }
                        // Rows fade and shrink with distance from the middle, which is
                        // what makes a plain scroll view read as a wheel.
                        .scrollTransition(.interactive, axis: .vertical) { content, phase in
                            content
                                .opacity(phase.isIdentity ? 1 : 0.25)
                                .scaleEffect(phase.isIdentity ? 1 : 0.9)
                        }
                        .id(value)
                }
            }
            .scrollTargetLayout()
        }
        .scrollIndicators(.hidden)
        .scrollTargetBehavior(.viewAligned)
        .scrollPosition(
            id: Binding(
                get: { minutes },
                set: { newValue in
                    if let newValue { minutes = newValue }
                }
            )
        )
        .frame(height: rowHeight * 5)
        .sensoryFeedback(.selection, trigger: minutes)
        .animation(.smooth(duration: 0.2), value: minutes)
    }
}
