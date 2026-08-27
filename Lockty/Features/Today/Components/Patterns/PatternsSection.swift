import SwiftUI

struct PatternsSection: View {
    let patterns: [BehaviorPattern]

    var body: some View {
        VStack(alignment: .leading, spacing: LocktySpacing.sm) {
            SectionHeader(title: "Patterns")

            VStack(spacing: LocktySpacing.sm) {
                ForEach(patterns) { pattern in
                    PatternCard(pattern: pattern)
                }
            }
        }
    }
}
