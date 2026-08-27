import SwiftUI

struct RoutineTriggersSheet: View {
    @Bindable var viewModel: RoutineEditorViewModel
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: LocktySpacing.lg) {
                    CardView(radius: LocktyRadius.medium, padding: LocktySpacing.md) {
                        HStack(spacing: LocktySpacing.md) {
                            Image(systemName: "hand.tap.fill")
                                .foregroundStyle(LocktyColors.secondaryText)
                            Text("Manual start is always available.")
                                .font(LocktyTypography.callout)
                                .foregroundStyle(LocktyColors.secondaryText)
                            Spacer()
                        }
                    }

                    CardView(radius: LocktyRadius.medium, padding: LocktySpacing.md) {
                        VStack(alignment: .leading, spacing: LocktySpacing.md) {
                            ToggleRow(
                                title: "Schedule",
                                subtitle: "Automatically start this routine on selected days.",
                                isOn: Binding(
                                    get: { viewModel.isScheduleEnabled },
                                    set: { viewModel.setScheduleEnabled($0) }
                                )
                            )

                            if let schedule = viewModel.scheduleTrigger {
                                ScheduleDaysPicker(
                                    selectedWeekdays: Binding(
                                        get: { schedule.weekdays },
                                        set: { newValue in viewModel.updateSchedule { $0.weekdays = newValue } }
                                    )
                                )

                                HStack(spacing: LocktySpacing.md) {
                                    Picker("Hour", selection: Binding(
                                        get: { schedule.hour },
                                        set: { newValue in viewModel.updateSchedule { $0.hour = newValue } }
                                    )) {
                                        ForEach(0..<24, id: \.self) { hour in
                                            Text(String(format: "%02d", hour)).tag(hour)
                                        }
                                    }
                                    .pickerStyle(.wheel)
                                    .frame(maxWidth: .infinity)

                                    Picker("Minute", selection: Binding(
                                        get: { schedule.minute },
                                        set: { newValue in viewModel.updateSchedule { $0.minute = newValue } }
                                    )) {
                                        ForEach([0, 15, 30, 45], id: \.self) { minute in
                                            Text(String(format: "%02d", minute)).tag(minute)
                                        }
                                    }
                                    .pickerStyle(.wheel)
                                    .frame(maxWidth: .infinity)
                                }
                                .frame(height: 120)
                            }
                        }
                    }
                }
                .padding(LocktySpacing.lg)
            }
            .locktyScreenBackground()
            .navigationTitle("Triggers")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { dismiss() }
                }
            }
        }
        .presentationDetents([.medium, .large])
    }
}
