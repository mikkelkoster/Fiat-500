import SwiftUI

/// The schedules, one card each with its own on/off, and Add. Tapping one opens the editor:
/// the time to leave, the days, and whether to skip when the car isn't plugged in. The car is
/// warm at the time shown; the app sends the command 20 minutes before, which the owner never
/// has to think about.
struct ScheduleSheet: View {
    @Environment(CarModel.self) private var model
    @Environment(\.dismiss) private var dismiss
    /// The schedule being edited; nil shows the list.
    @State private var draft: PreheatSchedule?
    @State private var isNew = false
    /// One of the car's own timers being edited.
    @State private var timerDraft: CarTimer?
    @State private var savingTimer: Int?
    @State private var timerError: String?

    var body: some View {
        Group {
            if let draft = Binding($draft) {
                ScheduleEditor(draft: draft, isNew: isNew,
                               onSave: { save($0) },
                               onDelete: { delete($0) },
                               onClose: { model.schedules.isEmpty ? dismiss() : close() })
                    .transition(.move(edge: .trailing).combined(with: .opacity))
            } else if let timer = Binding($timerDraft) {
                CarTimerEditor(timer: timer, saving: savingTimer != nil,
                               onSave: { saveTimer($0) },
                               onClose: { timerDraft = nil })
                    .transition(.move(edge: .trailing).combined(with: .opacity))
            } else {
                list.transition(.move(edge: .leading).combined(with: .opacity))
            }
        }
        .animation(.timingCurve(0.2, 0.8, 0.2, 1, duration: 0.4), value: draft == nil && timerDraft == nil)
        .background(V.surface.ignoresSafeArea())
        .varmeSheet([.height(draft != nil ? 680 : timerDraft != nil ? 760 : listHeight)])
        .onAppear {
            if model.schedules.isEmpty && model.carTimers == nil { add() }
        }
        .task { await model.loadCarTimers() }
    }

    // MARK: List

    private var list: some View {
        VStack(spacing: 0) {
            VSheetHeader(eyebrow: "Schedule", title: "Warm when you leave") { dismiss() }
            VStack(spacing: 10) {
                ForEach(model.schedules) { schedule in
                    ScheduleRow(schedule: schedule,
                                isOn: Binding(get: { schedule.isEnabled }, set: { on in
                                    var changed = schedule; changed.isEnabled = on; model.saveSchedule(changed)
                                })) {
                        isNew = false
                        draft = schedule
                    }
                }
            }
            .padding(.horizontal, V.gutter)
            .padding(.top, 20)

            if let timers = model.carTimers?.timers, !timers.isEmpty {
                VStack(alignment: .leading, spacing: 10) {
                    Text("In the car").eyebrowStyle().padding(.leading, 4)
                    ForEach(timers) { timer in
                        CarTimerRow(timer: timer, saving: savingTimer == timer.id,
                                    isOn: Binding(get: { timer.isOn }, set: { on in
                                        var changed = timer; changed.isOn = on; saveTimer(changed, close: false)
                                    })) { timerDraft = timer }
                    }
                    if let timerError {
                        Text(timerError).font(V.label).foregroundStyle(V.danger).padding(.leading, 4)
                    }
                }
                .padding(.horizontal, V.gutter)
                .padding(.top, 24)
            }

            Spacer(minLength: 0)
            VButton(title: "Add schedule", icon: "plus", glass: true) { add() }
                .padding(.horizontal, V.gutter)
                .padding(.top, 20)
                .padding(.bottom, 24)
        }
    }

    private var listHeight: CGFloat {
        let timers = model.carTimers?.timers.count ?? 0
        return min(820, 116 + CGFloat(model.schedules.count) * 98 + (timers > 0 ? 44 + CGFloat(timers) * 88 : 0) + 108)
    }

    /// Writes a timer to the car; the switch shows a spinner until the car confirms.
    private func saveTimer(_ timer: CarTimer, close: Bool = true) {
        savingTimer = timer.id
        timerError = nil
        Task {
            let result = await model.saveCarTimer(timer)
            savingTimer = nil
            switch result {
            case .failed(let message): timerError = message; Haptics.notify(.error)
            case .done(_, .failed, _): timerError = "The car didn't accept the change."; Haptics.notify(.error)
            default: Haptics.notify(.success); if close { timerDraft = nil }
            }
        }
    }

    // MARK: Actions

    private func add() {
        var schedule = PreheatSchedule()
        // A second schedule starts as the weekend one.
        if model.schedules.contains(where: { $0.weekdays == [2, 3, 4, 5, 6] }) {
            schedule.weekdays = [1, 7]
            schedule.readyHour = 9
            schedule.readyMinute = 0
        }
        isNew = true
        draft = schedule
    }

    private func close() {
        draft = nil
    }

    private func save(_ schedule: PreheatSchedule) {
        Haptics.notify(.success)
        model.saveSchedule(schedule)
        Task { await ScheduleCoordinator.shared.requestPermission() }
        close()
    }

    private func delete(_ schedule: PreheatSchedule) {
        model.deleteSchedule(schedule.id)
        if model.schedules.isEmpty { dismiss() } else { close() }
    }
}

/// One schedule in the list: the time large, the days under it, its own switch.
private struct ScheduleRow: View {
    let schedule: PreheatSchedule
    @Binding var isOn: Bool
    let edit: () -> Void

    var body: some View {
        HStack(spacing: 12) {
            Button(action: edit) {
                HStack(spacing: 12) {
                    VStack(alignment: .leading, spacing: 2) {
                        Text(schedule.readyTimeText).font(V.sora(34, .light)).tracking(-1)
                            .foregroundStyle(isOn ? V.text : V.textFaint)
                            .monospacedDigit()
                        Text(schedule.daysText).font(V.label).foregroundStyle(V.textMuted).lineLimit(1)
                    }
                    Spacer(minLength: 8)
                    PhIcon(name: "caret-right", size: 14).foregroundStyle(V.textFaint)
                }
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            VSwitch(isOn: $isOn)
        }
        .padding(.leading, 20).padding(.trailing, 12)
        .frame(height: 88)
        .background(RoundedRectangle(cornerRadius: V.radiusCard, style: .continuous).fill(V.raised))
    }
}

/// Editing one schedule.
private struct ScheduleEditor: View {
    @Binding var draft: PreheatSchedule
    let isNew: Bool
    let onSave: (PreheatSchedule) -> Void
    let onDelete: (PreheatSchedule) -> Void
    let onClose: () -> Void

    var body: some View {
        VStack(spacing: 0) {
            VSheetHeader(eyebrow: "Schedule", title: isNew ? "New schedule" : "Edit schedule", onClose: onClose)

            VStack(spacing: 16) {
                VStack(alignment: .leading, spacing: 0) {
                    Text("Leave at").font(V.label).foregroundStyle(V.textMuted)
                        .padding(.leading, 22).padding(.top, 18)
                    DatePicker("Leave at", selection: leaveAt, displayedComponents: .hourAndMinute)
                        .datePickerStyle(.wheel)
                        .labelsHidden()
                        .colorScheme(.dark)
                        .frame(maxWidth: .infinity)
                        .frame(height: 180)
                        .clipped()
                        .onChange(of: draft.readyTimeText) { _, _ in Haptics.select() }
                }
                .padding(.bottom, 8)
                .background(RoundedRectangle(cornerRadius: 28, style: .continuous).fill(V.raised))

                HStack(spacing: 0) {
                    ForEach(PreheatSchedule.weekOrder, id: \.self) { day in
                        if day != PreheatSchedule.weekOrder.first { Spacer(minLength: 4) }
                        let on = draft.weekdays.contains(day)
                        Button {
                            Haptics.select()
                            if on { draft.weekdays.remove(day) } else { draft.weekdays.insert(day) }
                        } label: {
                            Text(String(Calendar.current.veryShortWeekdaySymbols[day - 1]))
                                .font(on ? V.sora(14, .semibold) : V.sora(14))
                                .foregroundStyle(on ? V.ground : V.textMuted)
                                .frame(width: 46, height: 46)
                                .background(Circle().fill(on ? V.text : V.raised))
                        }
                        .buttonStyle(PressStyle())
                        .accessibilityLabel(Calendar.current.weekdaySymbols[day - 1])
                        .accessibilityAddTraits(on ? .isSelected : [])
                    }
                }

                VSwitchRow(title: "Only when plugged in", isOn: $draft.onlyWhenPluggedIn)
            }
            .padding(.horizontal, V.gutter)
            .padding(.top, 20)

            Spacer(minLength: 0)

            VStack(spacing: 8) {
                VButton(title: "Save schedule", glass: true) { onSave(draft) }
                    .disabled(draft.weekdays.isEmpty)
                    .opacity(draft.weekdays.isEmpty ? 0.5 : 1)
                if !isNew {
                    Button { onDelete(draft) } label: {
                        Text("Delete schedule").font(V.label).foregroundStyle(V.danger).frame(height: 44)
                    }
                }
            }
            .padding(.horizontal, V.gutter)
            .padding(.top, 24)
            .padding(.bottom, 24)
        }
    }

    /// The leave time as a date for the wheel; only the hour and minute matter.
    private var leaveAt: Binding<Date> {
        Binding(
            get: { Calendar.current.date(bySettingHour: draft.readyHour, minute: draft.readyMinute, second: 0, of: Date()) ?? Date() },
            set: { date in
                let parts = Calendar.current.dateComponents([.hour, .minute], from: date)
                draft.readyHour = parts.hour ?? draft.readyHour
                draft.readyMinute = parts.minute ?? draft.readyMinute
            }
        )
    }
}

/// One of the car's own timers in the list: what it does, when, and its switch.
private struct CarTimerRow: View {
    let timer: CarTimer
    let saving: Bool
    @Binding var isOn: Bool
    let edit: () -> Void

    var body: some View {
        HStack(spacing: 12) {
            Button(action: edit) {
                HStack(spacing: 12) {
                    PhIcon(name: timer.kind == .charge ? "lightning" : "flame", size: 18)
                        .foregroundStyle(isOn ? V.text : V.textFaint)
                    VStack(alignment: .leading, spacing: 2) {
                        Text(timer.timeText).font(V.sora(22, .light)).foregroundStyle(isOn ? V.text : V.textFaint).monospacedDigit()
                        Text("\(timer.title) · \(timer.daysText.isEmpty ? "No days" : timer.daysText)").font(V.label).foregroundStyle(V.textMuted).lineLimit(1)
                    }
                    Spacer(minLength: 8)
                    PhIcon(name: "caret-right", size: 14).foregroundStyle(V.textFaint)
                }
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            if saving { ProgressView().tint(V.text).frame(width: 51) } else { VSwitch(isOn: $isOn) }
        }
        .padding(.leading, 18).padding(.trailing, 12)
        .frame(height: 78)
        .background(RoundedRectangle(cornerRadius: V.radiusCard, style: .continuous).fill(V.raised))
    }
}

/// Editing one of the car's timers: start (and end, for charging), days, on/off. Saved to the car.
private struct CarTimerEditor: View {
    @Binding var timer: CarTimer
    let saving: Bool
    let onSave: (CarTimer) -> Void
    let onClose: () -> Void

    var body: some View {
        VStack(spacing: 0) {
            VSheetHeader(eyebrow: "In the car", title: timer.title, onClose: onClose)
            VStack(spacing: 12) {
                HStack(spacing: 10) {
                    wheel(timer.endHour == nil ? "At" : "From", hour: $timer.startHour, minute: $timer.startMinute)
                    if timer.endHour != nil {
                        wheel("Until", hour: Binding(get: { timer.endHour ?? 0 }, set: { timer.endHour = $0 }),
                              minute: Binding(get: { timer.endMinute ?? 0 }, set: { timer.endMinute = $0 }))
                    }
                }
                HStack(spacing: 0) {
                    ForEach(PreheatSchedule.weekOrder, id: \.self) { day in
                        if day != PreheatSchedule.weekOrder.first { Spacer(minLength: 4) }
                        let on = timer.weekdays.contains(day)
                        Button {
                            Haptics.select()
                            if on { timer.weekdays.remove(day) } else { timer.weekdays.insert(day) }
                        } label: {
                            Text(String(Calendar.current.veryShortWeekdaySymbols[day - 1]))
                                .font(on ? V.sora(14, .semibold) : V.sora(14))
                                .foregroundStyle(on ? V.ground : V.textMuted)
                                .frame(width: 46, height: 46)
                                .background(Circle().fill(on ? V.text : V.raised))
                        }
                        .buttonStyle(PressStyle())
                        .accessibilityLabel(Calendar.current.weekdaySymbols[day - 1])
                    }
                }
                VSwitchRow(title: timer.isOn ? "On" : "Off", isOn: $timer.isOn)
            }
            .padding(.horizontal, V.gutter)
            .padding(.top, 20)
            Spacer(minLength: 0)
            VButton(title: saving ? "Sending to the car…" : "Save to car", loading: saving, glass: true) { onSave(timer) }
                .allowsHitTesting(!saving)
                .padding(.horizontal, V.gutter)
                .padding(.top, 20).padding(.bottom, 24)
        }
    }

    private func wheel(_ label: String, hour: Binding<Int>, minute: Binding<Int>) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            Text(label).font(V.label).foregroundStyle(V.textMuted).padding(.leading, 18).padding(.top, 14)
            DatePicker(label, selection: Binding(
                get: { Calendar.current.date(bySettingHour: hour.wrappedValue, minute: minute.wrappedValue, second: 0, of: Date()) ?? Date() },
                set: { d in
                    let c = Calendar.current.dateComponents([.hour, .minute], from: d)
                    hour.wrappedValue = c.hour ?? 0; minute.wrappedValue = c.minute ?? 0
                }), displayedComponents: .hourAndMinute)
                .datePickerStyle(.wheel).labelsHidden().colorScheme(.dark)
                .frame(maxWidth: .infinity).frame(height: 160).clipped()
        }
        .background(RoundedRectangle(cornerRadius: 24, style: .continuous).fill(V.raised))
    }
}
