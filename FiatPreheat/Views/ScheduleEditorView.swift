import SwiftUI

struct ScheduleEditorView: View {
    @Environment(CarModel.self) private var model
    @Environment(\.dismiss) private var dismiss
    @State private var schedule: PreheatSchedule

    private let leadOptions = [10, 15, 20, 30, 45]

    init(schedule: PreheatSchedule) {
        _schedule = State(initialValue: schedule)
    }

    private var isNew: Bool { !model.schedules.contains { $0.id == schedule.id } }

    private var readyTime: Binding<Date> {
        Binding {
            Calendar.current.date(from: DateComponents(hour: schedule.readyHour, minute: schedule.readyMinute)) ?? .now
        } set: { date in
            let parts = Calendar.current.dateComponents([.hour, .minute], from: date)
            schedule.readyHour = parts.hour ?? 7
            schedule.readyMinute = parts.minute ?? 30
        }
    }

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    DatePicker("Warm by", selection: readyTime, displayedComponents: .hourAndMinute)
                        .datePickerStyle(.wheel)
                        .labelsHidden()
                        .frame(maxWidth: .infinity)
                }

                Section("Repeat") {
                    WeekdayPicker(selection: $schedule.weekdays)
                        .listRowInsets(EdgeInsets(top: 12, leading: 12, bottom: 12, trailing: 12))
                }

                Section {
                    Picker("Start", selection: $schedule.leadMinutes) {
                        ForEach(leadOptions, id: \.self) { Text("\($0) min before").tag($0) }
                    }
                } footer: {
                    Text("The car preheats to the temperature last set inside it. Preheating while plugged in saves range.")
                }

                if !isNew {
                    Section {
                        Button("Delete Schedule", role: .destructive) {
                            model.schedules.removeAll { $0.id == schedule.id }
                            dismiss()
                        }
                    }
                }
            }
            .navigationTitle(isNew ? "New Schedule" : "Edit Schedule")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") { save() }
                        .disabled(schedule.weekdays.isEmpty)
                }
            }
        }
        .presentationDetents([.large])
    }

    private func save() {
        if let index = model.schedules.firstIndex(where: { $0.id == schedule.id }) {
            model.schedules[index] = schedule
        } else {
            model.schedules.append(schedule)
        }
        model.schedules.sort { ($0.readyHour, $0.readyMinute) < ($1.readyHour, $1.readyMinute) }
        Task { await ScheduleCoordinator.shared.requestPermission() }
        dismiss()
    }
}

private struct WeekdayPicker: View {
    @Binding var selection: Set<Int>

    var body: some View {
        let symbols = Calendar.current.veryShortWeekdaySymbols
        HStack(spacing: 6) {
            ForEach(PreheatSchedule.weekOrder, id: \.self) { day in
                let isOn = selection.contains(day)
                Button {
                    if isOn { selection.remove(day) } else { selection.insert(day) }
                } label: {
                    Text(symbols[day - 1])
                        .font(.subheadline.weight(.semibold))
                        .frame(maxWidth: .infinity, minHeight: 40)
                        .foregroundStyle(isOn ? .white : .primary)
                        .background(isOn ? Color.preheat : Color(.tertiarySystemFill), in: .circle)
                }
                .buttonStyle(.plain)
                .accessibilityLabel(Calendar.current.weekdaySymbols[day - 1])
                .accessibilityAddTraits(isOn ? .isSelected : [])
            }
        }
    }
}
