import SwiftUI

struct HomeScreen: View {
    @Environment(CarModel.self) private var model
    @State private var sheet: Sheet?
    @State private var toast: ToastItem?
    @State private var confirmUnlock = false
    @State private var pull: CGFloat = 0
    @State private var refreshing = false

    enum Sheet: String, Identifiable { case find, schedule, settings, trips; var id: String { rawValue } }

    /// Everything under the hero: tiles, Heat cabin, the action row, the slider, the gaps, and a
    /// little air above the home indicator.
    private static let belowHero: CGFloat = V.tileHeight + 64 + 78 + 60 + V.cardGap * 4 + 6

    /// How far to pull before letting go refreshes.
    private let pullThreshold: CGFloat = 64

    var body: some View {
        ZStack(alignment: .top) {
            V.ground.ignoresSafeArea()
            // The page fits the screen, so it doesn't scroll: it only moves when pulled down to refresh.
            GeometryReader { geo in
                VStack(spacing: V.cardGap) {
                    hero(height: min(560, max(330, geo.size.height + geo.safeAreaInsets.top - Self.belowHero)))
                    tiles.padding(.horizontal, V.gutter)
                    preheatButton.padding(.horizontal, V.gutter)
                    actionTiles.padding(.horizontal, V.gutter)
                    UnlockSlider(locked: model.status?.isLocked ?? true, busy: model.isBusy || model.availability(of: .lock) != .available) { unlock in
                        if unlock { confirmUnlock = true } else { Task { await model.perform(.lock) } }
                    }
                    .padding(.horizontal, V.gutter)
                    Spacer(minLength: 0)
                }
                .offset(y: refreshing ? 64 : pull)
                .animation(.timingCurve(0.2, 0.8, 0.2, 1, duration: 0.35), value: refreshing)
                .contentShape(Rectangle())
                .gesture(
                    DragGesture(minimumDistance: 12)
                        .onChanged { drag in
                            guard !refreshing, drag.translation.height > 0, drag.translation.height > abs(drag.translation.width) else { return }
                            // Resists more the further it goes.
                            pull = 110 * (1 - 1 / (drag.translation.height / 110 + 1))
                        }
                        .onEnded { _ in
                            let release = pull >= pullThreshold * 0.8
                            withAnimation(.timingCurve(0.2, 0.8, 0.2, 1, duration: 0.35)) { pull = 0 }
                            if release, !refreshing { Task { await refresh() } }
                        }
                )
            }
            .ignoresSafeArea(edges: .top)
            // On top of the page, just under the Dynamic Island, in the gap the pull opens.
            refreshWheel
        }
        .overlay(alignment: .bottom) {
            if let toast { VToast(title: toast.title, detail: toast.detail, isError: toast.isError).padding(.bottom, 16).id(toast.id) }
        }
        .animation(.easeOut(duration: 0.25), value: toast)
        .preferredColorScheme(.dark)
        .sheet(item: $sheet) { which in
            switch which {
            case .find: FindCarSheet()
            case .schedule: ScheduleSheet()
            case .settings: SettingsSheet()
            case .trips: TripsSheet()
            }
        }
        .confirmationDialog("Unlock \(model.carName)?", isPresented: $confirmUnlock, titleVisibility: .visible) {
            Button("Unlock") { Task { await model.perform(.unlock) } }
        }
        .onChange(of: model.commandState) { _, state in show(ToastItem(state)) }
        .onChange(of: model.pendingSheet) { _, which in
            if which == "find" { sheet = .find; model.pendingSheet = nil }
        }
        .task {
            if Demo.isActive {
                switch Demo.screen {
                case "find": sheet = .find
                case "schedule": sheet = .schedule
                case "settings": sheet = .settings
                case "trips": sheet = .trips
                default: break
                }
                return
            }
            await model.refreshStatus()
        }
    }

    // MARK: Pieces

    private func hero(height: CGFloat) -> some View {
        CarHero(
            carName: model.carName,
            plate: model.plate,
            carColor: Color(hexString: model.carColorHex),
            image: model.carImage,
            heating: model.isPreheating,
            lightsOn: model.isLightsOn,
            lampsKnown: !model.paints.isEmpty,
            status: statusItems,
            updated: updatedText,
            height: height,
            onSettings: { sheet = .settings },
            cars: model.vehicles.map { v in (v.vin, v.vin == model.selectedVIN ? model.carName : (model.savedName(for: v) ?? v.nickname ?? v.model ?? "Car")) },
            onSwitchCar: { vin in Task { await model.switchCar(to: vin) } },
            onWake: model.availability(of: .deepRefresh) == .available ? { Task { await model.perform(.deepRefresh) } } : nil,
            waking: isRunning(.deepRefresh),
            onChargeNow: canChargeNow ? { Task { await model.perform(.chargeNow) } } : nil,
            chargeBusy: isRunning(.chargeNow)
        )
    }

    private func isRunning(_ command: RemoteCommand) -> Bool {
        switch model.commandState {
        case .sending(command), .waitingForCar(command): true
        default: false
        }
    }

    private var canChargeNow: Bool {
        guard let s = model.status, s.isPluggedIn == true, s.isCharging != true, (s.stateOfCharge ?? 0) < 100 else { return isRunning(.chargeNow) }
        return model.availability(of: .chargeNow) == .available
    }

    private var updatedText: String {
        guard let updated = model.status.map({ $0.reportedAt ?? $0.updatedAt }) else { return model.statusError == nil ? "Pull down to load" : "Couldn't reach the car" }
        let time = updated.formatted(date: .omitted, time: .shortened)
        return Calendar.current.isDateInToday(updated) ? "Updated \(time)" : "Updated \(updated.formatted(.dateTime.day().month(.abbreviated))) \(time)"
    }

    private var statusItems: [CarHero.StatusItem] {
        var items: [CarHero.StatusItem] = []
        if model.isPreheating { items.append(.init(text: "Warming", color: V.heat)) }
        if let locked = model.status?.isLocked {
            items.append(.init(text: locked ? "Locked" : "Unlocked", color: model.isPreheating ? nil : (locked ? V.positive : V.amber)))
        }
        if model.status?.isCharging == true { items.append(.init(text: "Charging")) }
        else if model.status?.isPluggedIn == true { items.append(.init(text: "Plugged in")) }
        return items
    }

    /// Battery and range: a readout on the page itself, no box, so it can't be mistaken for the
    /// glass buttons below. A hairline splits the two.
    private var tiles: some View {
        HStack(spacing: 20) {
            BatteryTile(status: model.status)
            Rectangle().fill(V.outline).frame(width: 1).padding(.vertical, 10)
            RangeTile(status: model.status, useMiles: model.useMiles)
        }
        .frame(height: V.tileHeight)
    }

    @ViewBuilder private var preheatButton: some View {
        if let phase = heatPhase {
            HeatingButton(phase: phase, minutesLeft: model.preheatMinutesLeft) { Task { await model.stopPreheat() } }
        } else {
            let connecting = model.commandState == .sending(.preconditionOn)
            VButton(title: connecting ? "Connecting…" : "Heat cabin", icon: "flame", height: 64, loading: connecting, glass: true) {
                Task { await model.startPreheat() }
            }
            // Busy stays white (it's saying "Connecting…"); it just ignores taps.
            .allowsHitTesting(!model.isBusy)
            .disabled(model.availability(of: .preconditionOn) != .available)
        }
    }

    /// Once the car has the start command, the heating button shows, and Stop works straight away,
    /// even while we're still waiting for the car to confirm.
    private var heatPhase: HeatingButton.Phase? {
        switch model.commandState {
        case .sending(.preconditionOff), .waitingForCar(.preconditionOff): return .stopping
        case .waitingForCar(.preconditionOn): return .starting
        default: return model.isPreheating ? .running : nil
        }
    }

    private var actionTiles: some View {
        HStack(spacing: 8) {
            ActionTile(icon: "lightbulb", title: model.isLightsOn ? "On" : "Lights", state: tileState(.lights, active: model.isLightsOn)) {
                Task { await model.perform(.lights) }
            }
            ActionTile(icon: "map-pin", title: "Find", state: tileState(.locate)) { sheet = .find }
            ActionTile(icon: "car", title: "Boot", state: tileState(.trunkUnlock)) { Task { await model.perform(.trunkUnlock) } }
            scheduleTile
        }
    }

    private var scheduleTile: some View {
        Button { sheet = .schedule } label: {
            VStack(spacing: 6) {
                if let next = model.nextSchedule {
                    Text(next.schedule.readyTimeText).font(V.button).tracking(-0.5).foregroundStyle(V.text)
                    Text(next.ready.formatted(.dateTime.weekday(.abbreviated))).font(V.label).foregroundStyle(V.textMuted)
                } else if !model.schedules.isEmpty {
                    PhIcon(name: "clock").foregroundStyle(V.textFaint)
                    Text("Off").font(V.label).foregroundStyle(V.textMuted)
                } else {
                    PhIcon(name: "clock").foregroundStyle(V.text)
                    Text("Schedule").font(V.label).foregroundStyle(V.text)
                }
            }
            .frame(maxWidth: .infinity).frame(height: 78)
            .glassTile()
            .contentShape(RoundedRectangle(cornerRadius: V.radiusCard, style: .continuous))
        }
        .buttonStyle(.plain)
    }

    private func tileState(_ command: RemoteCommand, active: Bool = false) -> ActionTile.State {
        switch model.commandState {
        case .sending(command), .waitingForCar(command): return .pending
        default: break
        }
        if active { return .active }
        return model.availability(of: command) == .available ? .idle : .unavailable
    }

    private var refreshWheel: some View {
        // Follows the finger while pulling; turns steadily, one turn a second, while refreshing.
        TimelineView(.animation(paused: !refreshing)) { context in
            let spin = context.date.timeIntervalSinceReferenceDate.truncatingRemainder(dividingBy: 1) * 360
            PhIcon(name: "wheel", size: 24)
                .foregroundStyle(V.text)
                .rotationEffect(.degrees(refreshing ? spin : Double(pull) * 4))
        }
        .opacity(refreshing ? 1 : min(1, Double(pull) / pullThreshold))
        .scaleEffect(refreshing ? 1 : 0.6 + 0.4 * min(1, pull / pullThreshold))
        .animation(.easeOut(duration: 0.2), value: refreshing)
        .padding(.top, 14)
        .allowsHitTesting(false)
        .onChange(of: pull >= pullThreshold * 0.8) { _, armed in if armed { Haptics.select() } }
    }

    /// Battery, range, lock state and where the car is, all at once.
    private func refresh() async {
        refreshing = true
        Haptics.tap()
        async let status: () = model.refreshStatus()
        async let location: () = model.loadLocation()
        // At least one full turn, so a quick answer still reads as a refresh.
        async let minimum: () = { try? await Task.sleep(for: .seconds(1)) }()
        _ = await (status, location, minimum)
        refreshing = false
    }

    private func show(_ item: ToastItem?) {
        guard let item else { return }
        toast = item
        Haptics.notify(item.isError ? .error : .success)
        Task {
            try? await Task.sleep(for: .seconds(item.isError ? 6 : 3.5))
            if toast?.id == item.id { toast = nil }
        }
    }
}

// MARK: - Tiles

struct BatteryTile: View {
    let status: VehicleStatus?
    @State private var sheen = false

    var body: some View {
        let soc = status?.stateOfCharge
        let charging = status?.isCharging == true
        let color = charging ? V.positive : V.batteryColor(soc)
        // Number first, then the bar, then what it is: big, line, small.
        VStack(alignment: .leading, spacing: 8) {
            HStack(alignment: .firstTextBaseline, spacing: 4) {
                Text(soc.map { "\(Int($0))" } ?? "–").font(V.number).tracking(-2).foregroundStyle(V.text)
                    .contentTransition(.numericText(value: soc ?? 0)).animation(.smooth, value: soc)
                Text("%").font(V.body).foregroundStyle(V.textMuted)
                Spacer(minLength: 4)
                if charging {
                    Text("Full \(fullBy)").font(V.label).foregroundStyle(V.textMuted).lineLimit(1).minimumScaleFactor(0.8)
                } else if let word = V.batteryWord(soc) {
                    Text(word).font(V.sora(11, .medium)).foregroundStyle(V.ground)
                        .lineLimit(1).minimumScaleFactor(0.8)
                        .padding(.horizontal, 7).padding(.vertical, 3)
                        .background(Capsule().fill(color))
                }
            }
            GeometryReader { g in
                ZStack(alignment: .leading) {
                    Capsule().fill(V.outline)
                    Capsule().fill(color)
                        .frame(width: g.size.width * CGFloat(min(100, max(0, soc ?? 0))) / 100)
                        .overlay(alignment: .leading) {
                            if charging {
                                LinearGradient(colors: [.white.opacity(0), .white.opacity(0.35), .white.opacity(0)], startPoint: .leading, endPoint: .trailing)
                                    .frame(width: g.size.width * 0.24)
                                    .offset(x: sheen ? g.size.width : -g.size.width * 0.24)
                            }
                        }
                        .clipShape(Capsule())
                        .shadow(color: charging ? V.positive.opacity(sheen ? 0.5 : 0.25) : .clear, radius: charging ? (sheen ? 10 : 6) : 0)
                }
            }
            .frame(height: 5)
            HStack(spacing: 5) {
                if charging { PhIcon(name: "lightning", size: 12).foregroundStyle(V.positive).opacity(sheen ? 1 : 0.6) }
                Text(charging ? "Charging" : "Battery").font(V.label).foregroundStyle(charging ? V.positive : V.textMuted)
            }
        }
        .padding(.vertical, 12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .onAppear { if charging { withAnimation(.timingCurve(0.4, 0, 0.2, 1, duration: 4.8).repeatForever(autoreverses: false)) { sheen = true } } }
        .onChange(of: charging) { _, on in
            sheen = false
            if on { withAnimation(.timingCurve(0.4, 0, 0.2, 1, duration: 4.8).repeatForever(autoreverses: false)) { sheen = true } }
        }
    }

    private var fullBy: String {
        // Fiat's own estimate when it sends one; otherwise a rough guess from the gap to full at 7 kW.
        if let minutes = status?.minutesToFull {
            return (status?.reportedAt ?? Date()).addingTimeInterval(minutes * 60).formatted(date: .omitted, time: .shortened)
        }
        let soc = status?.stateOfCharge ?? 0
        let hours = (100 - soc) / 100 * 42 / 7
        return Date().addingTimeInterval(hours * 3600).formatted(date: .omitted, time: .shortened)
    }
}

struct RangeTile: View {
    let status: VehicleStatus?
    let useMiles: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(alignment: .firstTextBaseline, spacing: 4) {
                Text(rangeValue).font(V.number).tracking(-2).foregroundStyle(V.text)
                    .contentTransition(.numericText()).animation(.smooth, value: rangeValue)
                Text(useMiles ? "mi" : "km").font(V.body).foregroundStyle(V.textMuted)
            }
            // Level with the battery bar, so the captions line up.
            Color.clear.frame(height: 5)
            Text("Range").font(V.label).foregroundStyle(V.textMuted)
        }
        .padding(.vertical, 12)
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var rangeValue: String {
        guard let range = status?.range else { return "–" }
        let unit = status?.rangeUnit?.lowercased() ?? "km"
        var km = range
        if unit.hasPrefix("mi") { km = range * 1.609 }
        return "\(Int(useMiles ? km / 1.609 : km))"
    }
}

// MARK: - Heating button

/// The preheat button while the cabin heats: a faint band drifts across inside every 5.2 s, the dot breathes.
struct HeatingButton: View {
    enum Phase { case starting, running, stopping }
    let phase: Phase
    let minutesLeft: Int
    let stop: () -> Void
    @State private var sweep = false
    @State private var pulse = false

    private var text: String {
        switch phase {
        case .starting: "Connecting to the car…"
        case .running: "Heating · \(minutesLeft) min left"
        case .stopping: "Stopping…"
        }
    }

    var body: some View {
        HStack {
            HStack(spacing: 10) {
                if phase == .running {
                    Circle().fill(V.heat).frame(width: 10, height: 10)
                        .scaleEffect(pulse ? 1.08 : 0.92).opacity(pulse ? 1 : 0.55)
                } else {
                    ProgressView().controlSize(.small).tint(V.heat)
                }
                Text(text).font(V.button).foregroundStyle(V.heat)
                    .lineLimit(1).minimumScaleFactor(0.8)
                    .contentTransition(.opacity)
            }
            .padding(.leading, 22)
            .animation(.easeInOut(duration: 0.3), value: phase)
            Spacer(minLength: 8)
            Button(action: stop) {
                Text("Stop").font(V.body).foregroundStyle(V.ground)
                    .padding(.horizontal, 16).frame(height: 44)
                    .background(Capsule().fill(V.heat))
            }
            .buttonStyle(PressStyle())
            .disabled(phase == .stopping)
            .opacity(phase == .stopping ? 0.5 : 1)
            .padding(.trailing, 10)
        }
        .frame(height: 64)
        .background(
            GeometryReader { g in
                ZStack {
                    Capsule().fill(V.activeFill(V.heat))
                    LinearGradient(colors: [V.heat.opacity(0), V.heat.opacity(0.07), Color(hex: 0xfed7aa).opacity(0.12), V.heat.opacity(0.07), V.heat.opacity(0)], startPoint: .leading, endPoint: .trailing)
                        .frame(width: g.size.width * 0.55)
                        .offset(x: sweep ? g.size.width * 1.1 : -g.size.width * 0.6)
                        .opacity(sweep ? 0 : 1)
                }
                .clipShape(Capsule())
            }
        )
        .overlay(Capsule().strokeBorder(V.heat, lineWidth: 1.5))
        .onAppear {
            withAnimation(.timingCurve(0.4, 0, 0.2, 1, duration: 5.2).repeatForever(autoreverses: false)) { sweep = true }
            withAnimation(.timingCurve(0.45, 0, 0.55, 1, duration: 2.4).repeatForever(autoreverses: true)) { pulse = true }
        }
    }
}

// MARK: - Action tile

struct ActionTile: View {
    enum State { case idle, active, pending, unavailable }
    let icon: String
    let title: String
    let state: State
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            VStack(spacing: 8) {
                PhIcon(name: icon)
                Text(title).font(V.label)
            }
            .foregroundStyle(state == .active ? V.amber : state == .pending ? V.textFaint : state == .unavailable ? V.textFaint : V.text)
            .frame(maxWidth: .infinity).frame(height: 78)
            .glassTile(tint: state == .active ? V.amber : nil)
            .contentShape(RoundedRectangle(cornerRadius: V.radiusCard, style: .continuous))
        }
        .buttonStyle(.plain)
        .disabled(state == .pending || state == .unavailable)
    }
}

// MARK: - Unlock slider

/// A 60 pt track with a white knob; drag it to the far end to unlock (or lock). The knob is
/// white whatever the state; the state reads in the status line.
struct UnlockSlider: View {
    let locked: Bool
    let busy: Bool
    let onComplete: (_ unlock: Bool) -> Void
    @State private var drag: CGFloat = 0

    var body: some View {
        GeometryReader { g in
            let travel = g.size.width - 50 - 10
            ZStack(alignment: .leading) {
                Color.clear.glassCapsule(tint: nil)
                Text(locked ? "SWIPE TO UNLOCK" : "SWIPE TO LOCK").font(V.eyebrow).tracking(3).foregroundStyle(V.textMuted)
                    .frame(maxWidth: .infinity).opacity(1 - Double(drag / travel) * 1.5)
                PhIcon(name: locked ? "lock" : "lock-open", size: 20).foregroundStyle(V.ground)
                    .frame(width: 50, height: 50)
                    .glassCapsule(tint: V.text)
                    .offset(x: 5 + drag)
                    .gesture(DragGesture()
                        .onChanged { drag = min(travel, max(0, $0.translation.width)) }
                        .onEnded { _ in
                            if drag >= travel * 0.85 { Haptics.notify(.success); onComplete(locked) }
                            withAnimation(.spring(response: 0.35, dampingFraction: 0.8)) { drag = 0 }
                        })
            }
        }
        .frame(height: 60)
        .opacity(busy ? 0.5 : 1)
        .disabled(busy)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(locked ? "Unlock" : "Lock")
        .accessibilityAddTraits(.isButton)
        .accessibilityAction { onComplete(locked) }
    }
}

// MARK: - Toast item

struct ToastItem: Equatable {
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
        .preconditionOn: "Heating", .preconditionOff: "Climate off", .lock: "Locked", .unlock: "Unlocked",
        .lights: "Lights on", .trunkUnlock: "Boot unlocked", .chargeNow: "Charging started",
        .deepRefresh: "Updated from the car", .locate: "Location updated",
    ]
    private static let sent: [RemoteCommand: String] = [
        .preconditionOn: "Heat sent", .preconditionOff: "Stop sent", .lock: "Lock sent", .unlock: "Unlock sent",
        .lights: "Lights sent", .trunkUnlock: "Boot unlock sent", .chargeNow: "Charge now sent",
        .deepRefresh: "Update requested", .locate: "Location requested",
    ]
}
