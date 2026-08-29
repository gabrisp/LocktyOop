import SwiftUI

/// The one way a section is titled: an uppercase eyebrow caption sitting above the
/// section's card, optionally preceded by a hairline separator, and optionally carrying
/// an (i) that explains the section in a popover.
///
/// Explanations live behind the (i) rather than as body copy under the title, so a
/// section stays visually quiet by default and every section explains itself the same way.
struct LocktySectionTitle: View {
    let title: String
    var info: String?
    var showsSeparator = true
    /// Optional trailing content, e.g. a count.
    var accessory: AnyView?

    @State private var isShowingInfo = false

    init(
        _ title: String,
        info: String? = nil,
        showsSeparator: Bool = true
    ) {
        self.title = title
        self.info = info
        self.showsSeparator = showsSeparator
        self.accessory = nil
    }

    init<Accessory: View>(
        _ title: String,
        info: String? = nil,
        showsSeparator: Bool = true,
        @ViewBuilder accessory: () -> Accessory
    ) {
        self.title = title
        self.info = info
        self.showsSeparator = showsSeparator
        self.accessory = AnyView(accessory())
    }

    var body: some View {
        VStack(alignment: .leading, spacing: LocktySpacing.sm) {
            if showsSeparator {
                Rectangle()
                    .fill(LocktyColors.separator)
                    .frame(height: 0.5)
            }

            HStack(spacing: LocktySpacing.xs) {
                Text(title.uppercased())
                    .locktyEyebrow()

                if let info {
                    Button {
                        isShowingInfo = true
                    } label: {
                        Image(systemName: "info.circle")
                            .font(.system(size: 13, weight: .light))
                            .foregroundStyle(LocktyColors.tertiaryText)
                    }
                    .buttonStyle(.plain)
                    .tappable()
                    .popover(isPresented: $isShowingInfo) {
                        Text(info)
                            .font(LocktyTypography.callout)
                            .foregroundStyle(LocktyColors.primaryText)
                            .frame(width: 240, alignment: .leading)
                            .padding(LocktySpacing.md)
                            .presentationCompactAdaptation(.popover)
                    }
                }

                Spacer(minLength: 0)

                accessory
            }
        }
    }
}
