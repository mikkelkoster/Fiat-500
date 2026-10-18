import SwiftUI

/// One schedule: on/off once it exists, the time to leave, the days, and whether to skip
/// when the car isn't plugged in. The car is warm at the time shown; the app sends the
/// command 20 minutes before, which the owner never has to think about.
struct ScheduleSheet: View {
    @Environment(CarModel.self) private var model
    @Environment(\.dismiss) private var dismiss
    @State private var draft = PreheatSchedule()
    @State private var isNew = true
    @State private var goingUp = true

    var body: some View {
        VStack(spacing: 0) {
            VSheetHeader(eyebrow: "Schedule", title: "Warm when you leave") { dismiss() }

            VStack(spacing: 16) {
                if !isNew {
                    VSwitchRow(title: draft.isEnabled ? "Schedule on" : "Schedule off",
                               detail: draft.isEnabled ? "Next: \(nextText)" : nil, isOn: $draft.isEnabled)
                }

                HStack(alignment: .center) {
                    VStack(alignment: .leading, spacing: 6) {
                        Text("Leave at").font(V.label).foregroundStyle(V.textMuted)
                        RollingText(text: draft.readyTimeText, font: V.display, up: goingUp)
                            .foregroundStyle(V.text)
                            .frame(height: 70)
                    }
                    Spacer()
                    VStack(spacing: 8) {
                        VRoundButton(icon: "caret-up", label: "Later") { step(15) }
                        VRoundButton(icon: "caret-down", label: "Earlier") { step(-15) }
                    }
                }
                .padding(.leading, 22).padding(.trailing, 16).padding(.vertical, 22)
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

            VStack(spacing: 8) {
                VButton(title: "Save · \(draft.daysText) \(draft.readyTimeText)") { save() }
                    .disabled(draft.weekdays.isEmpty)
                if !isNew {
                    Button { model.deleteSchedule(); dismiss() } label: {
                        Text("Delete schedule").font(V.label).foregroundStyle(V.danger).frame(height: 44)
                    }
                }
            }
            .padding(.horizontal, V.gutter)
            .padding(.top, 28)
            .padding(.bottom, 24)
        }
        .background(V.surface.ignoresSafeArea())
        .varmeSheet([.height(isNew ? 560 : 680)])
        .onAppear {
            if let existing = model.schedule { draft = existing; isNew = false }
        }
    }

    private var nextText: String {
        guard let next = draft.upcomingStarts(after: Date()).first else { return "–" }
        let ready = next.addingTimeInterval(TimeInterval(draft.leadMinutes * 60))
        return ready.formatted(.dateTime.weekday(.abbreviated).hour().minute())
    }

    private func step(_ minutes: Int) {
        Haptics.select()
        goingUp = minutes > 0
        var total = (draft.readyHour * 60 + draft.readyMinute + minutes + 24 * 60) % (24 * 60)
        total -= total % 15
        draft.readyHour = total / 60
        draft.readyMinute = total % 60
    }

    private func save() {
        Haptics.notify(.success)
        model.saveSchedule(draft)
        Task { await ScheduleCoordinator.shared.requestPermission() }
        dismiss()
    }
}
