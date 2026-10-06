import SwiftUI

struct HomeView: View {
    @Environment(CarModel.self) private var model
    @State private var showSettings = false
    @State private var editing: PreheatSchedule?
    @State private var toast: ToastMessage?

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 0) {
                header
                CardStack {
                    BatteryCard(status: model.status, error: model.statusError)
                    ClimateCard()
                    SchedulesSection(editing: $editing)
                }
                .padding(.horizontal, Space.gutter)
                .padding(.top, Space.firstCard)
                .padding(.bottom, 96)
            }
        }
        .background(Ink.background.ignoresSafeArea())
        .refreshable { await model.refreshStatus() }
        .overlay(alignment: .bottom) {
            if let toast {
                Toast(title: toast.title, detail: toast.detail)
                    .toastPlacement()
                    .id(toast.id)
            }
        }
        .animation(.easeOut(duration: Motion.normal), value: toast)
        .sheet(isPresented: $showSettings) { SettingsView() }
        .sheet(item: $editing) { schedule in ScheduleEditorView(schedule: schedule) }
        .onChange(of: model.commandState) { _, state in show(ToastMessage(state)) }
        .task {
            if Demo.isActive {
                switch Demo.screen {
                case "settings": showSettings = true
                case "schedule": editing = model.schedules.first
                default: break
                }
                return
            }
            if model.hasAccount {
                await model.refreshStatus()
            } else {
                showSettings = true
            }
        }
    }

    private var header: some View {
        HStack(alignment: .center, spacing: 12) {
            Text("500e").font(Type.page).tracking(Type.pageTitleTracking).foregroundStyle(Ink.foreground)
            LicensePlate(text: model.plate)
            Spacer()
            SmallButton(title: "Settings") { showSettings = true }
        }
        .padding(.horizontal, Space.gutter)
        .padding(.top, 20)
    }

    private func show(_ message: ToastMessage?) {
        guard let message else { return }
        toast = message
        Haptics.notify(message.isError ? .error : .success)
        Task {
            try? await Task.sleep(for: .seconds(message.isError ? 6 : 3.5))
            if toast?.id == message.id { toast = nil }
        }
    }
}

/// What the last command did, said once at the foot of the screen.
private struct ToastMessage: Equatable {
    let id = UUID()
    let title: String
    var detail: String? = nil
    var isError = false

    init?(_ state: CarModel.CommandState) {
        switch state {
        case .idle, .sending, .waitingForCar:
            return nil
        case .failed(let message):
            title = "Couldn't reach the car"; detail = message; isError = true
        case .done(_, .failed, _):
            title = "The car didn't accept it"; detail = "Check it's parked with enough charge."; isError = true
        case .done(.preconditionOn, .succeeded, _):
            title = "Preheating"
        case .done(.preconditionOn, .unknown, _):
            title = "Preheat sent"; detail = "The car hasn't confirmed yet."
        case .done(.preconditionOff, _, _):
            title = "Climate off"
        }
    }
}

// MARK: - Battery

private struct BatteryCard: View {
    let status: VehicleStatus?
    let error: String?

    var body: some View {
        Card {
            VStack(alignment: .leading, spacing: 0) {
                HStack {
                    Text("Battery").eyebrowStyle()
                    Spacer()
                    if status?.isCharging == true {
                        DayTag(text: "Charging", tone: .good)
                    } else if status?.isPluggedIn == true {
                        DayTag(text: "Plugged in")
                    }
                }
                HStack(alignment: .firstTextBaseline, spacing: 4) {
                    Text(status?.stateOfCharge.map { "\(Int($0))" } ?? "–")
                        .font(Type.displayNumber).foregroundStyle(Ink.foreground)
                        .contentTransition(.numericText())
                    Text("%").font(Type.number).foregroundStyle(Ink.muted)
                }
                .padding(.top, 8)
                Text(rangeLine)
                    .font(Type.emphasis).foregroundStyle(Ink.secondary)
                    .padding(.top, 4)
                if let error {
                    Text(error).font(Type.footnote).foregroundStyle(Ink.redText)
                        .lineLimit(2)
                        .padding(.top, 12)
                }
            }
        }
        .animation(Motion.change, value: status)
    }

    private var rangeLine: String {
        guard let status else { return "Pull down to load" }
        let range = status.range.map { "\(Int($0)) \(status.rangeUnit?.lowercased() ?? "km") range" } ?? "Range unknown"
        return "\(range) · updated \(status.updatedAt.formatted(date: .omitted, time: .shortened))"
    }
}

// MARK: - Climate

private struct ClimateCard: View {
    @Environment(CarModel.self) private var model

    var body: some View {
        // Re-read `isPreheating` once a minute so the card falls back when the run ends.
        TimelineView(.periodic(from: .now, by: 60)) { _ in
            let active = model.isPreheating
            Card {
                VStack(alignment: .leading, spacing: 0) {
                    HStack {
                        Text("Climate").font(Type.heading).tracking(-0.3).foregroundStyle(Ink.foreground)
                        Spacer()
                        if active { DayTag(text: "On", tone: .good) }
                    }
                    Text(line(active: active))
                        .font(Type.body).foregroundStyle(Ink.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                        .padding(.top, 6)
                        .animation(.default, value: model.commandState)

                    Group {
                        if active {
                            PrimaryButton(title: busyTitle ?? "Stop", icon: "stop.fill", outline: true) {
                                Task { await model.stopPreheat() }
                            }
                        } else {
                            PrimaryButton(title: busyTitle ?? "Preheat now", icon: "thermometer.sun.fill") {
                                Task { await model.startPreheat() }
                            }
                        }
                    }
                    .disabled(model.isBusy || !model.hasAccount)
                    .padding(.top, 20)
                }
            }
        }
    }

    private var busyTitle: String? {
        switch model.commandState {
        case .sending: "Sending…"
        case .waitingForCar: "Waiting for the car…"
        default: nil
        }
    }

    private func line(active: Bool) -> String {
        if active, let start = model.lastPreheatStart {
            return "Preheating since \(start.formatted(date: .omitted, time: .shortened)). The car stops by itself."
        }
        return "Heats or cools the cabin to the temperature last set in the car."
    }
}

// MARK: - Schedules

private struct SchedulesSection: View {
    @Environment(CarModel.self) private var model
    @Binding var editing: PreheatSchedule?

    var body: some View {
        CardSection(title: "Schedules", help: "Warm when you leave") {
            SmallButton(title: "Add", icon: "plus") { editing = PreheatSchedule() }
        } content: {
            if model.schedules.isEmpty {
                Card {
                    Text("Add a time, such as weekdays at 07:30, and the car starts preheating before it.")
                        .font(Type.body).foregroundStyle(Ink.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
            } else {
                VStack(spacing: 0) {
                    ForEach(model.schedules) { schedule in
                        row(schedule, isEnabled: enabledBinding(schedule.id))
                            .rowRule(schedule.id != model.schedules.last?.id)
                    }
                }
                .cardSurface()
            }
        }
    }

    private func enabledBinding(_ id: UUID) -> Binding<Bool> {
        Binding {
            model.schedules.first { $0.id == id }?.isEnabled ?? false
        } set: { on in
            guard let index = model.schedules.firstIndex(where: { $0.id == id }) else { return }
            model.schedules[index].isEnabled = on
        }
    }

    private func row(_ s: PreheatSchedule, isEnabled: Binding<Bool>) -> some View {
        HStack(spacing: 12) {
            Button {
                Haptics.select()
                editing = s
            } label: {
                VStack(alignment: .leading, spacing: 3) {
                    Text(s.readyTimeText).font(Type.number).foregroundStyle(s.isEnabled ? Ink.foreground : Ink.subtle)
                    Text("\(s.daysText) · starts \(String(format: "%02d:%02d", s.start.hour, s.start.minute))")
                        .font(Type.footnote).foregroundStyle(Ink.muted)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            // WeeklySwitchStyle draws its label beside the switch, so the label stays empty here.
            Toggle(isOn: isEnabled) { EmptyView() }
                .toggleStyle(WeeklySwitchStyle())
                .accessibilityLabel("\(s.readyTimeText) schedule")
        }
        .padding(.horizontal, Space.cardPadding)
        .padding(.vertical, 14)
    }
}

// MARK: - Plate

/// The car's Danish number plate: white, red frame, EU band with "DK". A real-world object, so it
/// keeps its own colours whatever the theme.
struct LicensePlate: View {
    let text: String

    private var formatted: String {
        let compact = text.replacingOccurrences(of: " ", with: "").uppercased()
        guard compact.count > 2 else { return compact }
        return "\(compact.prefix(2)) \(compact.dropFirst(2))"
    }

    var body: some View {
        HStack(spacing: 0) {
            Text("DK")
                .font(Type.inter(9, .semibold))
                .foregroundStyle(.white)
                .frame(width: 16)
                .frame(maxHeight: .infinity)
                .background(Color(hex: 0x1E40AF))
            Text(formatted)
                .font(Type.inter(15, .semibold).monospacedDigit())
                .foregroundStyle(Color(hex: 0x0C0A09))
                .padding(.horizontal, 7)
        }
        .frame(height: 26)
        .background(Color.white)
        .clipShape(RoundedRectangle(cornerRadius: Radius.small - 2, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: Radius.small - 2, style: .continuous).strokeBorder(Color(hex: 0xDC2626), lineWidth: 1.5))
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Plate \(text)")
    }
}
