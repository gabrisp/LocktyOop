import FamilyControls
import SwiftUI

struct AppUsageRow: View {
    let state: AppUsageState
    let onClassificationChange: (AppClassification) -> Void
    let onSelected: (() -> Void)?

    var body: some View {
        HStack(spacing: LocktySpacing.md) {
            AppIconView(
                source: state.app.iconSource,
                applicationToken: state.app.applicationToken,
                fallbackSystemImage: state.app.iconSystemName,
                size: 56,
                chrome: .plain
            )

            VStack(alignment: .leading, spacing: LocktySpacing.xs) {
                Group {
                    if let token = state.app.applicationToken {
                        Label(token)
                            .labelStyle(.socialFeedTag)
                    } else {
                        Text(state.app.displayName)
                    }
                }
                .font(LocktyTypography.headline)
                .foregroundStyle(LocktyColors.primaryText)
                .lineLimit(1)

                ClassificationMenu(
                    classification: state.classification,
                    onClassificationChange: onClassificationChange
                )

                if let comparisonText = state.comparisonText {
                    Text(comparisonText)
                        .font(.caption2.weight(.medium))
                        .foregroundStyle(LocktyColors.tertiaryText)
                        .locktyNumericTransition(trigger: comparisonText)
                }
            }

            Spacer()

            Text(state.durationText)
                .font(LocktyTypography.headline)
                .monospacedDigit()
                .foregroundStyle(LocktyColors.primaryText)
                .locktyNumericTransition(trigger: state.durationText)
        }
        .contentShape(Rectangle())
        .onTapGesture {
            onSelected?()
        }
    }
}

private struct ClassificationMenu: View {
    let classification: AppClassification
    let onClassificationChange: (AppClassification) -> Void

    var body: some View {
        Menu {
            ForEach(AppClassification.allCases) { option in
                Button(option.title) {
                    onClassificationChange(option)
                }
            }
        } label: {
            HStack(spacing: LocktySpacing.xs) {
                Circle()
                    .fill(LocktyColors.classification(classification))
                    .frame(width: 7, height: 7)

                Text(classification.title)
                    .font(LocktyTypography.caption)
                    .foregroundStyle(LocktyColors.classification(classification))
            }
            .tappable()
            .animation(.smooth(duration: 0.2), value: classification)
        }
        .buttonStyle(.plain)
        .accessibilityLabel("Classification")
        .accessibilityValue(classification.title)
    }
}


extension LabelStyle where Self == SocialFeedTagLabelStyle {
 static var socialFeedTag: SocialFeedTagLabelStyle {
     SocialFeedTagLabelStyle()
 }
}
struct SocialFeedTagLabelStyle: LabelStyle {
 @ScaledMetric(relativeTo: .footnote) private var iconWidth = 14.0
 func makeBody(configuration: Configuration) -> some View {
     HStack {
         configuration.title
             .font(.caption2)
             .foregroundStyle(.red)
 }
 .compositingGroup()
 .font(.caption)
 }
}
