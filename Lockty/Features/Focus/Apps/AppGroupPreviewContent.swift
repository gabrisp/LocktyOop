import FamilyControls
import ManagedSettings
import SwiftUI

/// A group at rest: which apps are in it, with nothing to fill in.
///
/// The fourth of these, after routines, rules and frictions, and for the same reason:
/// opening a group dropped you straight into the form that made it, so reading one meant
/// reading a name field and a row that says "3 apps". A group is a folder, and the first
/// thing to show is the folder.
struct AppGroupPreviewContent: View {
    let name: String
    let applicationTokens: [ApplicationToken]
    /// Handed the way into editing, when there is one. Holding a line is the same gesture
    /// as pressing the pencil, on the thing being described.
    var onEdit: (() -> Void)?

    private var count: Int { applicationTokens.count }

    var body: some View {
        VStack(spacing: LocktySpacing.lg) {
            AppFolderCard(
                title: name,
                subtitle: count == 1 ? "1 item" : "\(count) items",
                tokens: applicationTokens,
                titleAlignment: .center
            )

            VStack(spacing: 2) {
                Text(subtitleLine)
                    .font(.system(.subheadline, design: .default, weight: .regular))
                    .foregroundStyle(LocktyColors.secondaryText)
                    .lineLimit(1)

                Text(name)
                    .font(.system(size: 34, weight: .bold))
                    .foregroundStyle(LocktyColors.primaryText)
                    .multilineTextAlignment(.center)
                    .lineLimit(2)
                    .minimumScaleFactor(0.7)
            }

            summaryCard
        }
        .frame(maxWidth: .infinity)
        .padding(.horizontal, LocktySpacing.screenInset)
        .padding(.top, LocktySpacing.sm)
        .padding(.bottom, LocktySpacing.md)
    }

    private var subtitleLine: String {
        "Group · \(count == 1 ? "1 app" : "\(count) apps")"
    }

    private var summaryCard: some View {
        VStack(spacing: 0) {
            row("Apps") {
                HStack(spacing: LocktySpacing.sm) {
                    if !applicationTokens.isEmpty {
                        LocktyStackedAppTokens(tokens: applicationTokens)
                    }
                    Text(count == 1 ? "1 app" : "\(count) apps")
                }
            }

            Divider()
                .overlay(LocktyColors.separator.opacity(0.45))

            // What a group is for, said once. It is the only thing about a group that is
            // not visible in the folder above, and the reason one is worth making.
            row("Used by") {
                Text("Routines and rules")
            }
        }
        .padding(.horizontal, LocktySpacing.cardInset)
        .locktyCardBackground(cornerRadius: 26)
    }

    private func row<Value: View>(
        _ title: String,
        @ViewBuilder value: () -> Value
    ) -> some View {
        HStack(spacing: LocktySpacing.md) {
            Text(title)
                .font(.system(.body, design: .default, weight: .regular))
                .foregroundStyle(LocktyColors.primaryText)

            Spacer(minLength: LocktySpacing.sm)

            value()
                .font(.system(.body, design: .default, weight: .regular))
                .foregroundStyle(LocktyColors.secondaryText)
                .lineLimit(1)
        }
        .frame(minHeight: 56)
        .locktyEditOnLongPress(onEdit)
    }
}
