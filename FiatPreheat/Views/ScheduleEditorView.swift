import SwiftUI

struct ScheduleEditorView: View {
    @Environment(CarModel.self) private var model
    @Environment(\.dismiss) private var dismiss
    @State private var schedule: PreheatSchedule

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

    private var startText: String {
        String(format: "%02d:%02d", schedule.start.hour, schedule.start.minute)
    }

    var body: some View {
        VStack(spacing: 0) {
            SheetHeader(
                title: isNew ? "New schedule" : "Edit schedule",
                subtitle: "The car starts preheating at \(startText)."
            ) { dismiss() }

            ScrollView {
                VStack(alignment: .leading, spacing: Space.formField) {
                    field("Warm by") {
                        DatePicker("Warm by", selection: readyTime, displayedComponents: .hourAndMinute)
                            .datePickerStyle(.wheel)
                            .labelsHidden()
                            .frame(maxWidth: .infinity)
                            .frame(height: 150)
                            .clipped()
                            .cardSurface(corner: Radius.panel)
                    }

                    field("Repeat") {
                        DayPicker(days: PreheatSchedule.weekOrder, selected: schedule.weekdays) { day in
                            if schedule.weekdays.contains(day) {
                                schedule.weekdays.remove(day)
                            } else {
                                schedule.weekdays.insert(day)
                            }
                        }
                    }

                    HStack {
                        VStack(alignment: .leading, spacing: 3) {
                            Text("Start before").font(Type.emphasis).foregroundStyle(Ink.foreground)
                            Text("15–20 min is usually enough").font(Type.footnote).foregroundStyle(Ink.muted)
                        }
                        Spacer()
                        NumberStepper(
                            value: "\(schedule.leadMinutes)",
                            unit: "min",
                            canDecrease: schedule.leadMinutes > 5,
                            canIncrease: schedule.leadMinutes < 60,
                            decrease: { schedule.leadMinutes -= 5 },
                            increase: { schedule.leadMinutes += 5 }
                        )
                    }

                    Text("It preheats to the temperature last set in the car. Preheating while plugged in saves range.")
                        .font(Type.footnote).foregroundStyle(Ink.muted)
                        .fixedSize(horizontal: false, vertical: true)
                }
                .padding(.horizontal, Space.gutter)
                .padding(.bottom, 24)
            }

            VStack(spacing: 10) {
                PrimaryButton(title: "Save") { save() }
                    .disabled(schedule.weekdays.isEmpty)
                if !isNew {
                    PrimaryButton(title: "Delete schedule", outline: true, tint: Ink.redText) {
                        model.schedules.removeAll { $0.id == schedule.id }
                        dismiss()
                    }
                }
            }
            .padding(.horizontal, Space.gutter)
            .padding(.top, 12)
            .padding(.bottom, 8)
        }
        .torqueSheet([.large])
    }

    private func field<Content: View>(_ label: String, @ViewBuilder content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(label).eyebrowStyle()
            content()
        }
    }

    private func save() {
        if let index = model.schedules.firstIndex(where: { $0.id == schedule.id }) {
            model.schedules[index] = schedule
        } else {
            model.schedules.append(schedule)
        }
        model.schedules.sort { ($0.readyHour, $0.readyMinute) < ($1.readyHour, $1.readyMinute) }
        Haptics.notify(.success)
        Task { await ScheduleCoordinator.shared.requestPermission() }
        dismiss()
    }
}
