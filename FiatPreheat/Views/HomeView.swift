import SwiftUI

struct HomeView: View {
    @Environment(CarModel.self) private var model
    @State private var showSettings = false
    @State private var editing: PreheatSchedule?
    @State private var showFindCar = false
    @State private var toast: ToastMessage?

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 0) {
                header
                CardStack {
                    BatteryCard(status: model.status, error: model.statusError)
                    ClimateCard()
                    CarCard(showFindCar: $showFindCar)
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
        .sheet(isPresented: $showFindCar) { FindCarView() }
        .onChange(of: model.commandState) { _, state in show(ToastMessage(state)) }
        .task {
            if Demo.isActive {
                switch Demo.screen {
                case "settings": showSettings = true
                case "schedule": editing = model.schedules.first
                case "find": showFindCar = true
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
        case .done(let command, .failed, _):
            title = "The car didn't accept it"; isError = true
            detail = command == .preconditionOn ? "Check it's parked with enough charge." : "It may be asleep or out of coverage. Try again in a minute."
        case .done(let command, .succeeded, _):
            title = Self.confirmed[command] ?? "Done"
        case .done(let command, .unknown, _):
            title = Self.sent[command] ?? "Sent"; detail = "The car hasn't confirmed yet."
        }
    }

    private static let confirmed: [RemoteCommand: String] = [
        .preconditionOn: "Preheating", .preconditionOff: "Climate off",
        .lock: "Locked", .unlock: "Unlocked", .lights: "Lights on",
        .trunkUnlock: "Boot unlocked", .chargeNow: "Charging started",
        .deepRefresh: "Updated from the car", .locate: "Location updated",
    ]

    private static let sent: [RemoteCommand: String] = [
        .preconditionOn: "Preheat sent", .preconditionOff: "Stop sent",
        .lock: "Lock sent", .unlock: "Unlock sent", .lights: "Lights sent",
        .trunkUnlock: "Boot unlock sent", .chargeNow: "Charge now sent",
        .deepRefresh: "Update requested", .locate: "Location requested",
    ]
}

// MARK: - Battery

private struct BatteryCard: View {
    @Environment(CarModel.self) private var model
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
                if showsRefresh || showsChargeNow {
                    HStack(spacing: 8) {
                        if showsRefresh {
                            SmallButton(title: "Update from car", icon: "arrow.clockwise") {
                                Task { await model.perform(.deepRefresh) }
                            }
                        }
                        if showsChargeNow {
                            SmallButton(title: "Charge now", icon: "bolt.fill") {
                                Task { await model.perform(.chargeNow) }
                            }
                        }
                    }
                    .disabled(model.isBusy)
                    .padding(.top, 12)
                }
            }
        }
        .animation(Motion.change, value: status)
    }

    /// Pull to refresh reads what Fiat's server last heard; this wakes the car for fresh numbers.
    private var showsRefresh: Bool { model.availability(of: .deepRefresh) == .available }

    /// Only when the cable is in but the car's own charging timer is holding back.
    private var showsChargeNow: Bool {
        model.availability(of: .chargeNow) == .available && status?.isPluggedIn == true && status?.isCharging != true
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

// MARK: - Car

/// Doors, lights, boot and finding the car: Fiat's "My Remote" commands.
private struct CarCard: View {
    @Environment(CarModel.self) private var model
    @Binding var showFindCar: Bool
    @State private var confirmUnlock = false

    private struct Action: Identifiable {
        let command: RemoteCommand
        let title: String
        let icon: String
        var id: String { command.rawValue }
    }

    private let actions = [
        Action(command: .lock, title: "Lock", icon: "lock.fill"),
        Action(command: .unlock, title: "Unlock", icon: "lock.open.fill"),
        Action(command: .lights, title: "Lights", icon: "lightbulb.fill"),
        Action(command: .trunkUnlock, title: "Open boot", icon: "car.side.rear.open"),
        Action(command: .locate, title: "Find car", icon: "location.fill"),
    ]

    var body: some View {
        let shown = actions.filter { model.availability(of: $0.command) != .unsupported }
        if !shown.isEmpty {
            Card {
                VStack(alignment: .leading, spacing: 0) {
                    HStack {
                        Text("Car").font(Type.heading).tracking(-0.3).foregroundStyle(Ink.foreground)
                        Spacer()
                        if let locked = model.status?.isLocked {
                            DayTag(text: locked ? "Locked" : "Unlocked", tone: locked ? .good : .caution)
                        }
                    }
                    Text(line(shown))
                        .font(Type.body).foregroundStyle(Ink.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                        .padding(.top, 6)
                    LazyVGrid(columns: [GridItem(.flexible(), spacing: 10), GridItem(.flexible(), spacing: 10)], spacing: 10) {
                        ForEach(shown) { action in
                            PrimaryButton(title: title(action), icon: action.icon, outline: true) { tap(action.command) }
                                .disabled(model.isBusy || !model.hasAccount
                                          || model.availability(of: action.command) != .available)
                        }
                    }
                    .padding(.top, 20)
                }
            }
            .confirmationDialog("Unlock the car?", isPresented: $confirmUnlock, titleVisibility: .visible) {
                Button("Unlock") { Task { await model.perform(.unlock) } }
            } message: {
                Text("The doors unlock wherever the car is.")
            }
        }
    }

    private func tap(_ command: RemoteCommand) {
        switch command {
        case .unlock: confirmUnlock = true
        // Opens on the last known spot; asking the car for a new one happens inside.
        case .locate: showFindCar = true
        default: Task { await model.perform(command) }
        }
    }

    /// The button that's working says so instead of its name.
    private func title(_ action: Action) -> String {
        switch model.commandState {
        case .sending(action.command): "Sending…"
        case .waitingForCar(action.command): "Waiting…"
        default: action.title
        }
    }

    private func line(_ shown: [Action]) -> String {
        if shown.contains(where: { model.availability(of: $0.command) == .needsSubscription }) {
            return "Some of these need Fiat's My Remote package. Buy it in the Fiat app, then pull down to refresh."
        }
        return "Each command asks the car through Fiat's servers and can take up to a minute."
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
