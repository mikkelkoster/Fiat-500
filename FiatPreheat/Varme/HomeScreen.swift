import SwiftUI

struct HomeScreen: View {
    @Environment(CarModel.self) private var model
    @State private var sheet: Sheet?
    @State private var toast: ToastItem?
    @State private var confirmUnlock = false
    @State private var pull: CGFloat = 0
    @State private var refreshing = false
    /// Which gauge shows, battery or range; kept between launches.
    @AppStorage("gaugePage") private var gaugePage = 0

    enum Sheet: String, Identifiable { case find, schedule, settings, trips; var id: String { rawValue } }

    /// The gauge's height and how far it reaches up over the car.
    private static let gaugeHeight: CGFloat = 184
    private static let gaugeOverlap: CGFloat = 104

    /// Everything under the hero: the gauge (less its overlap), Heat cabin, the action row, the
    /// slider, the gaps, and a little air above the home indicator.
    private static let belowHero: CGFloat = gaugeHeight - gaugeOverlap + 64 + 78 + 60 + V.cardGap * 4 + 6

    /// How far to pull before letting go refreshes.
    private let pullThreshold: CGFloat = 64

    var body: some View {
        ZStack(alignment: .top) {
            V.ground.ignoresSafeArea()
            // The page fits the screen, so it doesn't scroll: it only moves when pulled down to refresh.
            GeometryReader { geo in
                VStack(spacing: V.cardGap) {
                    hero(height: min(640, max(380, geo.size.height + geo.safeAreaInsets.top - Self.belowHero)))
                    // Free on the page, reaching up over the car's wheels.
                    gauges.padding(.top, -Self.gaugeOverlap)
                    HStack(spacing: 10) {
                        preheatButton
                        if canChargeNow { chargeButton.transition(.scale.combined(with: .opacity)) }
                    }
                    .animation(.easeOut(duration: 0.25), value: canChargeNow)
                    .padding(.horizontal, V.gutter)
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
                // Alongside the gauge's own sideways paging, not instead of it.
                .simultaneousGesture(
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
            case .schedule: ScheduleSheet(startsEmpty: model.schedules.isEmpty)
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
            ground: model.carGround,
            updated: updatedText,
            height: height,
            onSettings: { sheet = .settings },
            cars: model.vehicles.map { v in (v.vin, v.vin == model.selectedVIN ? model.carName : (model.savedName(for: v) ?? v.nickname ?? v.model ?? "Car")) },
            onSwitchCar: { vin in Task { await model.switchCar(to: vin) } }
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

    /// Battery and range as two gauges you swipe between, free on the page: read-only, so nothing
    /// like the glass buttons below. Both colour by charge; range is measured against the best
    /// full-charge range this car has shown.
    private var gauges: some View {
        let soc = model.status?.stateOfCharge
        let charging = model.status?.isCharging == true
        let color = charging ? V.positive : V.batteryColor(soc)
        let range = model.rangeKm.map { model.useMiles ? $0 / 1.609 : $0 }
        let note: ArcGauge.Note? = charging ? .text("Full \(fullBy)") : V.batteryWord(soc).map { .badge($0, color) }
        return VStack(spacing: 8) {
            TabView(selection: $gaugePage) {
                ArcGauge(fraction: (soc ?? 0) / 100, color: color, value: soc.map { "\(Int($0))" } ?? "–", unit: "%",
                         caption: charging ? "Charging" : "Battery", captionColor: charging ? V.positive : V.textMuted, note: note)
                    .tag(0)
                ArcGauge(fraction: model.rangeFraction, color: color, value: range.map { "\(Int($0))" } ?? "–",
                         unit: model.useMiles ? "mi" : "km", caption: "Range", captionColor: V.textMuted, note: nil)
                    .tag(1)
            }
            .tabViewStyle(.page(indexDisplayMode: .never))
            .frame(width: 200, height: 160)
            .onChange(of: gaugePage) { _, _ in Haptics.select() }
            HStack(spacing: 7) {
                ForEach(0..<2, id: \.self) { i in
                    Circle().fill(i == gaugePage ? V.text : V.outline).frame(width: 6, height: 6)
                }
            }
            .animation(.easeOut(duration: 0.2), value: gaugePage)
        }
        .frame(maxWidth: .infinity)
        .frame(height: Self.gaugeHeight)
        // A soft dark pool behind the gauge, so it reads where it overlaps the car.
        .background(
            RadialGradient(colors: [V.ground.opacity(0.95), V.ground.opacity(0)], center: .center, startRadius: 40, endRadius: 150)
                .offset(y: -6)
        )
        // VoiceOver hears both, without swiping.
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(gaugeSummary)
    }

    private var gaugeSummary: String {
        var parts: [String] = []
        if let soc = model.status?.stateOfCharge { parts.append("Battery \(Int(soc)) percent") }
        if let km = model.rangeKm { parts.append(model.useMiles ? "range \(Int(km / 1.609)) miles" : "range \(Int(km)) kilometres") }
        if model.status?.isCharging == true { parts.append("charging, full \(fullBy)") }
        return parts.isEmpty ? "Battery not loaded yet" : parts.joined(separator: ", ")
    }

    /// Fiat's own estimate when it sends one; otherwise a rough guess from the gap to full at 7 kW.
    private var fullBy: String {
        if let minutes = model.status?.minutesToFull {
            return (model.status?.reportedAt ?? Date()).addingTimeInterval(minutes * 60).formatted(date: .omitted, time: .shortened)
        }
        let soc = model.status?.stateOfCharge ?? 0
        return Date().addingTimeInterval((100 - soc) / 100 * 42 / 7 * 3600).formatted(date: .omitted, time: .shortened)
    }

    /// Next to Heat cabin while the car is plugged in and not charging.
    private var chargeButton: some View {
        Button { Task { await model.perform(.chargeNow) } } label: {
            Group {
                if isRunning(.chargeNow) { ProgressView().tint(V.positive) } else { PhIcon(name: "lightning", size: 24) }
            }
            .foregroundStyle(V.positive)
            .frame(width: 64, height: 64)
            .glassCircle()
            .contentShape(Circle())
        }
        .buttonStyle(.plain)
        .disabled(isRunning(.chargeNow))
        .accessibilityLabel("Charge now")
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
        // The numbers are only as new as the car's last report; if that's old, ask the car itself.
        // That takes a minute or so; a note says when it's in.
        if !Demo.isActive, model.isStale, model.availability(of: .deepRefresh) == .available, !model.isBusy {
            Task { await model.perform(.deepRefresh) }
        }
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

// MARK: - Gauge

/// A 270° arc, open at the bottom: the value large in the middle, what it is under it, and a note
/// (a "Low" badge, or when charging will finish) in the opening.
struct ArcGauge: View {
    enum Note { case badge(String, Color), text(String) }

    let fraction: Double
    let color: Color
    let value: String
    let unit: String
    let caption: String
    let captionColor: Color
    let note: Note?

    var body: some View {
        ZStack {
            Circle().trim(from: 0, to: 0.75)
                .stroke(V.outline.opacity(0.7), style: StrokeStyle(lineWidth: 7, lineCap: .round))
                .rotationEffect(.degrees(135))
            Circle().trim(from: 0, to: 0.75 * max(0.01, min(1, fraction)))
                .stroke(color, style: StrokeStyle(lineWidth: 7, lineCap: .round))
                .rotationEffect(.degrees(135))
                .shadow(color: color.opacity(0.35), radius: 8)
                .animation(.timingCurve(0.2, 0.8, 0.2, 1, duration: 0.8), value: fraction)
            VStack(spacing: 0) {
                HStack(alignment: .firstTextBaseline, spacing: 3) {
                    Text(value).font(V.sora(52, .ultraLight)).tracking(-2).foregroundStyle(V.text)
                        .contentTransition(.numericText()).animation(.smooth, value: value)
                    Text(unit).font(V.sora(17)).foregroundStyle(V.textMuted)
                }
                Text(caption).font(V.label).foregroundStyle(captionColor)
            }
            .offset(y: 4)
            if let note {
                Group {
                    switch note {
                    case .text(let text):
                        Text(text).font(V.label).foregroundStyle(V.textMuted)
                    case .badge(let text, let tint):
                        Text(text).font(V.sora(11, .medium)).foregroundStyle(V.ground)
                            .padding(.horizontal, 8).padding(.vertical, 3)
                            .background(Capsule().fill(tint))
                    }
                }
                .offset(y: 62)
            }
        }
        .frame(width: 148, height: 148)
        .frame(maxWidth: .infinity)
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
                // Unlocked is the state to notice: knob, words and edge turn amber.
                Color.clear.glassCapsule(tint: nil)
                    .overlay(Capsule().strokeBorder(locked ? .clear : V.amber.opacity(0.5), lineWidth: 1))
                Text(locked ? "SWIPE TO UNLOCK" : "SWIPE TO LOCK").font(V.eyebrow).tracking(3).foregroundStyle(locked ? V.textMuted : V.amber)
                    .frame(maxWidth: .infinity).opacity(1 - Double(drag / travel) * 1.5)
                PhIcon(name: locked ? "lock" : "lock-open", size: 20).foregroundStyle(V.ground)
                    .frame(width: 50, height: 50)
                    .glassCapsule(tint: locked ? V.text : V.amber)
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
