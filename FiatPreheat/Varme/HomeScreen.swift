import SwiftUI

struct HomeScreen: View {
    @Environment(CarModel.self) private var model
    @Environment(\.scenePhase) private var phase
    @State private var sheet: Sheet?
    @State private var toast: ToastItem?
    @State private var pull: CGFloat = 0
    @State private var refreshing = false
    /// Which gauge shows, battery or range; kept between launches.
    @AppStorage("gaugePage") private var gaugePage = 0

    enum Sheet: String, Identifiable { case find, schedule, settings, trips; var id: String { rawValue } }

    /// The gauge at its natural size, and the header above it.
    private static let gaugeHeight: CGFloat = 200
    private static let heroHeight: CGFloat = 196

    /// Everything but the gauge: the header, the facts row, Climate, the action row, the slider,
    /// the gaps and a little air above the home indicator.
    private static let aroundGauge: CGFloat = heroHeight + 20 + 60 + 78 + 60 + V.cardGap * 6 + 8

    /// The gauge grows into the room the screen has, up to 45 % larger; smaller iPhones get it
    /// a little smaller than natural rather than pushing the slider off the screen.
    private static func gaugeScale(screenHeight: CGFloat) -> CGFloat {
        min(1.45, max(0.85, (screenHeight - aroundGauge - 16) / (gaugeHeight + 5)))
    }

    /// How far to pull before letting go refreshes.
    private let pullThreshold: CGFloat = 64

    var body: some View {
        ZStack(alignment: .top) {
            V.ground.ignoresSafeArea()
            // The page fits the screen, so it doesn't scroll: it only moves when pulled down to refresh.
            GeometryReader { geo in
                VStack(spacing: V.cardGap) {
                    let scale = Self.gaugeScale(screenHeight: geo.size.height + geo.safeAreaInsets.top)
                    hero
                    Spacer(minLength: 0)
                    // No picture of the car: the gauge is the hero, with the facts under it.
                    gauges.scaleEffect(scale).frame(height: Self.gaugeHeight * scale)
                    factsRow.padding(.top, 4)
                    Spacer(minLength: 0)
                    HStack(spacing: 10) {
                        if offers(.preconditionOn) { preheatButton }
                        if canChargeNow { chargeButton.transition(.scale.combined(with: .opacity)) }
                    }
                    .animation(.easeOut(duration: 0.25), value: canChargeNow)
                    .padding(.horizontal, V.gutter)
                    actionTiles.padding(.horizontal, V.gutter)
                    UnlockSlider(locked: model.status?.isLocked ?? true,
                                 pending: isRunning(.unlock) ? true : isRunning(.lock) ? false : nil,
                                 busy: model.isBusy || model.availability(of: .lock) != .available) { unlock in
                        // The full slide is the confirmation; no question on top of it.
                        Task { await model.perform(unlock ? .unlock : .lock) }
                    }
                    .padding(.horizontal, V.gutter)
                    .padding(.bottom, 8)
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
        .onChange(of: model.commandState) { _, state in show(ToastItem(state, status: model.status)) }
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
                await model.loadWeather()
            }
        }
        // Read Fiat again whenever the app comes to the front, then every minute while it's open,
        // so charging creeps up on screen without pulling. These are reads of what the car last
        // reported, not wake-ups, so they don't touch the car or its 12 V battery.
        .task(id: phase) {
            guard phase == .active, !Demo.isActive else { return }
            async let location: () = model.loadLocation()
            await model.refreshStatus()
            await location
            await model.loadWeather()
            while !Task.isCancelled {
                try? await Task.sleep(for: .seconds(model.status?.isCharging == true ? 30 : 60))
                guard !Task.isCancelled, !refreshing else { continue }
                await model.refreshStatus()
            }
        }
    }

    // MARK: Pieces

    private var hero: some View {
        CarHero(
            carName: model.carName,
            plate: model.plate,
            updated: updatedText,
            height: Self.heroHeight,
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
        if Demo.isSample { return "Nothing is sent to a car" }
        return statusText
    }

    /// The numbers are only as new as the car's last report. Say that plainly: a fresh report is
    /// "Updated", an old one "Car reported", and while the car is being asked, say so.
    private var statusText: String {
        guard let reported = model.status.map({ $0.reportedAt ?? $0.updatedAt }) else {
            return model.statusError == nil ? "Loading…" : "Couldn't reach the car · pull to retry"
        }
        let clock = reported.formatted(date: .omitted, time: .shortened)
        let calendar = Calendar.current
        let time = calendar.isDateInToday(reported) ? clock
            : calendar.isDateInYesterday(reported) ? "yesterday \(clock)"
            : "\(reported.formatted(.dateTime.day().month(.abbreviated))) \(clock)"
        switch model.wakeState {
        case .waking: return "Waking the car…"
        // Said once, short enough to fit beside the plate; then back to the report time.
        case .failed(let why): return why
        case .idle: return model.isStale ? "Reported \(time)" : "Updated \(time)"
        }
    }

    /// Battery and range as two gauges you swipe between, free on the page: read-only, so nothing
    /// like the glass buttons below. Both colour by charge; range is measured against the best
    /// full-charge range this car has shown.
    private var gauges: some View {
        let soc = model.status?.stateOfCharge
        let charging = model.status?.isCharging == true
        let color = charging ? V.positive : V.batteryColor(soc)
        let range = model.rangeKm.map { model.useMiles ? $0 / 1.609 : $0 }
        let fuel = model.status?.fuelLevel
        let pages = gaugePages
        // The range takes the colour of what it runs on: the battery, or the tank.
        let rangeColor = soc == nil && fuel != nil ? V.batteryColor(fuel) : color
        let page = Binding(get: { min(gaugePage, pages.count - 1) }, set: { gaugePage = $0 })
        return GaugePager(page: page, count: pages.count) { index, active in
            switch pages[index] {
            case .battery:
                ArcGauge(fraction: (soc ?? 0) / 100, color: color, value: soc, unit: "%",
                         caption: charging ? "Charging" : "Battery", captionColor: charging ? V.positive : V.textMuted,
                         captionIcon: charging ? "lightning" : "battery", active: active)
            case .fuel:
                ArcGauge(fraction: (fuel ?? 0) / 100, color: V.batteryColor(fuel), value: fuel, unit: "%",
                         caption: "Fuel", captionColor: V.textMuted, captionIcon: "gas-pump", active: active)
            case .range:
                ArcGauge(fraction: model.rangeFraction, color: rangeColor, value: range,
                         unit: model.useMiles ? "mi" : "km", caption: "Range", captionColor: V.textMuted,
                         captionIcon: "road", active: active)
            }
        }
        .frame(maxWidth: .infinity)
        .frame(height: Self.gaugeHeight)
        // A soft dark pool behind the gauge, so it reads where it overlaps the car. Drawn larger
        // than the gauge and gone well before its own edge, so it never ends in a line.
        .background {
            RadialGradient(colors: [V.ground.opacity(0.92), V.ground.opacity(0.5), V.ground.opacity(0)],
                           center: .center, startRadius: 30, endRadius: 150)
                .frame(width: 380, height: 340)
                .offset(y: -6)
                .allowsHitTesting(false)
        }
        // VoiceOver hears both, without swiping.
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(gaugeSummary)
    }

    // MARK: Temperature

    /// One quiet line under the gauge: the temperature (inside where the car says, else outside;
    /// blue when it's cold enough to want warming, orange when hot enough to want cooling), the
    /// odometer, the climate's setting where the car reports it, and a low 12 V battery in red.
    /// When it doesn't fit, the least important go first.
    private var factsRow: some View {
        let status = model.status
        let inside = status?.cabinTemperature
        var facts: [(icon: String, text: String, color: Color, keep: Bool)] = []
        if let c = inside ?? model.outsideTemperature {
            facts.append(("thermometer", inside != nil ? "Inside \(Self.degrees(c))" : "\(Self.degrees(c)) outside",
                          c < 5 ? V.cool : c > 25 ? V.heat : V.textMuted, true))
        }
        if let km = status?.odometerKm {
            let value = model.useMiles ? km / 1.609 : km
            facts.append(("road", "\(value.formatted(.number.precision(.fractionLength(0)))) \(model.useMiles ? "mi" : "km")", V.textMuted, false))
        }
        if let t = status?.targetTemperature { facts.append(("wind", "Set to \(Self.degrees(t))", V.textMuted, false)) }
        if let v = status?.auxBatteryVolts, v < CarAlerts.lowVolts {
            facts.append(("battery", String(format: "12 V low · %.1f V", v), V.danger, true))
        }
        func row(_ items: [(icon: String, text: String, color: Color, keep: Bool)]) -> some View {
            HStack(spacing: 18) {
                ForEach(items.indices, id: \.self) { i in
                    HStack(spacing: 5) {
                        PhIcon(name: items[i].icon, size: 14)
                        Text(items[i].text).font(V.label).lineLimit(1)
                    }
                    .foregroundStyle(items[i].color)
                }
            }
        }
        return ViewThatFits(in: .horizontal) {
            row(facts)
            row(facts.filter(\.keep))
        }
        .frame(height: 20)
        .padding(.horizontal, V.gutter)
        .accessibilityElement(children: .combine)
    }

    /// "4°" in the phone's own unit (°F in the US).
    static func degrees(_ celsius: Double) -> String {
        let fahrenheit = Locale.current.measurementSystem == .us
        let value = fahrenheit ? celsius * 9 / 5 + 32 : celsius
        return "\(Int(value.rounded()))°"
    }

    private enum GaugePage { case battery, fuel, range }

    /// Electric: battery and range. Plug-in hybrid: battery, fuel and range. Petrol or diesel:
    /// fuel and range. Before anything is read, the battery page shows it's loading.
    private var gaugePages: [GaugePage] {
        let status = model.status
        var pages: [GaugePage] = []
        if status?.stateOfCharge != nil || status?.fuelLevel == nil { pages.append(.battery) }
        if status?.fuelLevel != nil { pages.append(.fuel) }
        pages.append(.range)
        return pages
    }

    private var gaugeSummary: String {
        var parts: [String] = []
        if let soc = model.status?.stateOfCharge { parts.append("Battery \(Int(soc)) percent") }
        if let fuel = model.status?.fuelLevel { parts.append("fuel \(Int(fuel)) percent") }
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
            .frame(width: 60, height: 60)
            .glassCircle()
            .contentShape(Circle())
        }
        .buttonStyle(.plain)
        .disabled(isRunning(.chargeNow))
        .accessibilityLabel("Charge now")
    }

    private var preheatButton: some View {
        HeatControl(phase: heatPhase, minutesLeft: model.preheatMinutesLeft,
                    canStart: model.availability(of: .preconditionOn) == .available && !model.isBusy,
                    start: { Task { await model.startPreheat() } },
                    stop: { Task { await model.stopPreheat() } })
    }

    /// Stop works as soon as the car has the start command, even before it confirms.
    private var heatPhase: HeatControl.Phase {
        switch model.commandState {
        case .sending(.preconditionOff), .waitingForCar(.preconditionOff): return .stopping
        case .sending(.preconditionOn): return .connecting
        case .waitingForCar(.preconditionOn): return .starting
        default: return model.isPreheating ? .running : .idle
        }
    }

    private var actionTiles: some View {
        HStack(spacing: 8) {
            // Only what the car offers; one it offers without the subscription still shows, greyed.
            if offers(model.findCommand) {
                let horn = model.findCommand == .hornLights
                ActionTile(icon: "sun", title: horn ? "Horn & lights" : "Flash lights", busyTitle: horn ? "Honking…" : "Flashing…",
                           state: tileState(model.findCommand)) {
                    Task { await model.perform(model.findCommand) }
                }
            }
            if offers(.locate) {
                ActionTile(icon: "map-pin", title: "Find", busyTitle: "Locating…", state: tileState(.locate)) { sheet = .find }
            }
            if offers(model.bootUnlockCommand) { bootTile }
            // Schedules start the heating, so they go where the heating does.
            if offers(.preconditionOn) { scheduleTile }
        }
    }

    /// A car that doesn't list a command at all doesn't get its button. (One that lists it
    /// without the subscription keeps it, greyed, so the owner knows it's there to have.)
    private func offers(_ command: RemoteCommand) -> Bool {
        model.availability(of: command) != .unsupported
    }

    /// Boot: unlocks it, and while it's unlocked says so in red; then a tap locks it again.
    private var bootTile: some View {
        let unlocked = model.status?.isTrunkLocked == false
        let open = model.bootUnlockCommand
        let locking = isRunning(.trunkLock) || isRunning(.liftgateLock) || (unlocked && isRunning(.lock))
        let state: ActionTile.State = isRunning(open) || locking ? .pending
            : unlocked ? .alert : tileState(open)
        return ActionTile(icon: "boot", title: unlocked ? "Unlocked" : open == .liftgateUnlock ? "Liftgate" : "Boot",
                          busyTitle: locking ? "Locking…" : "Unlocking…", state: state) {
            Task { await model.perform(unlocked ? model.bootLockCommand : open) }
        }
        .accessibilityLabel(unlocked ? "Boot unlocked. Lock" : "Unlock boot")
    }

    private var scheduleTile: some View {
        Button { sheet = .schedule } label: {
            VStack(spacing: 6) {
                if let next = model.nextSchedule {
                    Text(next.schedule.readyTimeText).font(V.sora(19, .semibold)).tracking(-0.5).foregroundStyle(V.text)
                    Text(next.ready.formatted(.dateTime.weekday(.abbreviated))).font(V.sora(14)).foregroundStyle(V.textMuted)
                } else if !model.schedules.isEmpty {
                    PhIcon(name: "clock", size: 26).foregroundStyle(V.textFaint)
                    Text("Off").font(V.sora(14)).foregroundStyle(V.textMuted)
                } else {
                    PhIcon(name: "clock", size: 26).foregroundStyle(V.text)
                    Text("Schedule").font(V.sora(14)).foregroundStyle(V.text)
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
        await model.loadWeather()
        // The numbers are only as new as the car's last report; if that's old, ask the car itself.
        // That takes a minute or so, quietly; the numbers update when it answers.
        if !Demo.isActive, model.isStale, !model.isBusy {
            Task { await model.wakeQuietly() }
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

/// A 270° arc, open at the bottom, glowing in its colour: the value large in the middle and what
/// it is under it.
struct ArcGauge: View {
    let fraction: Double
    let color: Color
    /// Nil while there's nothing to show yet: the gauge shows it's loading.
    let value: Double?
    let unit: String
    let caption: String
    let captionColor: Color
    /// A small sign before the caption: what the number is.
    var captionIcon: String? = nil
    /// The page on show: it fills and counts up when the app opens and each time it's swiped to.
    var active = true

    @State private var shown: Double = 0

    /// Fill and count share one spring, so the number lands with the arc.
    private static let fill = Animation.spring(response: 1.1, dampingFraction: 0.86)

    var body: some View {
        let target = value ?? 0
        let progress = target > 0 ? shown / target : 0
        ZStack {
            Circle().trim(from: 0, to: 0.75)
                .stroke(V.outline.opacity(0.7), style: StrokeStyle(lineWidth: 8, lineCap: .round))
                .rotationEffect(.degrees(135))
            if value == nil {
                LoadingArc()
            } else {
                filledArc(progress: progress)
            }
            VStack(spacing: 0) {
                if value == nil {
                    LoadingNumber()
                } else {
                    HStack(alignment: .firstTextBaseline, spacing: 3) {
                        // The final number, hidden, holds the width; the counting one sits over it.
                        Text("\(Int(target.rounded()))")
                            .font(V.sora(60, .ultraLight)).tracking(-2).monospacedDigit()
                            .hidden()
                            .overlay(alignment: .trailing) {
                                Color.clear.modifier(CountUp(value: shown)).fixedSize()
                            }
                        Text(unit).font(V.sora(17)).foregroundStyle(V.textMuted)
                    }
                }
                HStack(spacing: 5) {
                    if let captionIcon { PhIcon(name: captionIcon, size: 14) }
                    Text(caption).font(V.label)
                }
                .foregroundStyle(captionColor)
            }
            .offset(y: 4)
        }
        .frame(width: 176, height: 176)
        // A tap fills it again from empty.
        .contentShape(Circle())
        .onTapGesture {
            guard value != nil else { return }
            Haptics.select()
            replay(after: 0.02)
        }
        .frame(maxWidth: .infinity)
        .animation(.easeOut(duration: 0.3), value: value == nil)
        // On opening, wait for the launch transition so the fill is seen.
        .onAppear { if active { replay(after: 0.35) } }
        .onChange(of: active) { _, isActive in
            if isActive {
                replay()
            } else {
                // Stay full while sliding out; empty once gone, ready to fill when it comes back.
                Task {
                    try? await Task.sleep(for: .milliseconds(450))
                    if !active {
                        var reset = Transaction()
                        reset.disablesAnimations = true
                        withTransaction(reset) { shown = 0 }
                    }
                }
            }
        }
        .onChange(of: value) { old, new in
            guard active else { return }
            // The first numbers in (after loading) fill from empty; later ones move from where it is.
            if old == nil { replay() } else { withAnimation(Self.fill) { shown = new ?? 0 } }
        }
    }

    /// The glow (a wide, soft copy of the arc under it), the arc with a tight halo, and a marker
    /// where it ends, riding along it as it fills.
    @ViewBuilder private func filledArc(progress: Double) -> some View {
        let end = max(0.01, min(1, fraction * progress))
        Circle().trim(from: 0, to: 0.75 * end)
            .stroke(color, style: StrokeStyle(lineWidth: 18, lineCap: .round))
            .rotationEffect(.degrees(135))
            .blur(radius: 16)
            .opacity(0.75)
        Circle().trim(from: 0, to: 0.75 * end)
            .stroke(color, style: StrokeStyle(lineWidth: 8, lineCap: .round))
            .rotationEffect(.degrees(135))
            .shadow(color: color.opacity(0.9), radius: 5)
            .shadow(color: color.opacity(0.5), radius: 12)
        ArcKnob(fraction: end)
            .fill(V.text)
            .shadow(color: color.opacity(0.8), radius: 6)
            .shadow(color: .black.opacity(0.5), radius: 1.5)
    }

    /// From empty to the value, again.
    private func replay(after delay: Double = 0.12) {
        var reset = Transaction()
        reset.disablesAnimations = true
        withTransaction(reset) { shown = 0 }
        withAnimation(Self.fill.delay(delay)) { shown = value ?? 0 }
    }
}

/// While the gauge waits for its first numbers: a short soft light sweeping along the empty arc.
private struct LoadingArc: View {
    var body: some View {
        TimelineView(.animation) { context in
            // One pass every 1.4 s, easing in and out, then on again from the start.
            let t = context.date.timeIntervalSinceReferenceDate.truncatingRemainder(dividingBy: 1.4) / 1.4
            let eased = t < 0.5 ? 2 * t * t : 1 - pow(-2 * t + 2, 2) / 2
            let length = 0.22
            let head = eased * (1 + length)
            let from = max(0, head - length), to = min(1, head)
            ZStack {
                Circle().trim(from: 0.75 * from, to: 0.75 * to)
                    .stroke(V.text.opacity(0.35), style: StrokeStyle(lineWidth: 14, lineCap: .round))
                    .blur(radius: 10)
                Circle().trim(from: 0.75 * from, to: 0.75 * to)
                    .stroke(LinearGradient(colors: [V.text.opacity(0), V.text.opacity(0.7)], startPoint: .leading, endPoint: .trailing),
                            style: StrokeStyle(lineWidth: 8, lineCap: .round))
            }
            .rotationEffect(.degrees(135))
        }
        .accessibilityHidden(true)
    }
}

/// Where the number will be: a soft bar, breathing.
private struct LoadingNumber: View {
    @State private var dim = false
    var body: some View {
        RoundedRectangle(cornerRadius: 10, style: .continuous)
            .fill(V.raised)
            .frame(width: 88, height: 46)
            .opacity(dim ? 0.45 : 0.9)
            .padding(.vertical, 12)
            .onAppear {
                withAnimation(.easeInOut(duration: 0.9).repeatForever(autoreverses: true)) { dim = true }
            }
    }
}

/// A dot on a 270° arc (open at the bottom, filling clockwise from the lower left), at `fraction` of
/// the way along. A shape, so it's animated along the curve rather than straight across.
struct ArcKnob: Shape {
    var fraction: Double
    var size: CGFloat = 16
    var animatableData: Double {
        get { fraction }
        set { fraction = newValue }
    }

    func path(in rect: CGRect) -> Path {
        let radius = min(rect.width, rect.height) / 2
        let angle = (135 + 270 * fraction) * .pi / 180
        let centre = CGPoint(x: rect.midX + radius * cos(angle), y: rect.midY + radius * sin(angle))
        return Path(ellipseIn: CGRect(x: centre.x - size / 2, y: centre.y - size / 2, width: size, height: size))
    }
}

/// The gauge's number, counting with the animation rather than jumping to its end.
private struct CountUp: ViewModifier, Animatable {
    var value: Double
    var animatableData: Double {
        get { value }
        set { value = newValue }
    }

    func body(content: Content) -> some View {
        Text("\(Int(value.rounded()))")
            .font(V.sora(60, .ultraLight)).tracking(-2).foregroundStyle(V.text)
            .monospacedDigit()
            // Each frame is its own number; no cross-fade between them.
            .contentTransition(.identity)
    }
}

// MARK: - Gauge pager

/// Pages you swipe between, with a little spring as they settle and a dot that stretches across to
/// the next one and draws itself in after it.
struct GaugePager<Content: View>: View {
    @Binding var page: Int
    let count: Int
    @ViewBuilder let content: (_ index: Int, _ active: Bool) -> Content

    @State private var drag: CGFloat = 0
    /// Decided at the start of each drag: sideways pages, up or down is left to the page.
    @State private var sideways: Bool?
    /// The dot indicator's two ends, in page units: the head leads, the tail follows.
    @State private var head: CGFloat = 0
    @State private var tail: CGFloat = 0

    /// How far a drag goes for a whole page.
    private let width: CGFloat = 250

    var body: some View {
        // The arc's opening is empty, so the dots sit up in it.
        VStack(spacing: -4) {
            // In place, not a strip: each page sits where it'd be (−1 left, 0 here, 1 right) and is
            // shifted a little, shrunk a little and faded by that much.
            ZStack {
                ForEach(0..<count, id: \.self) { i in
                    let position = CGFloat(i - page) + drag / width
                    let away = min(1, abs(position))
                    // One out, then the other in: the leaving gauge is gone by halfway, the next
                    // only shows past it, so they never overlap.
                    content(i, i == page)
                        .frame(width: width)
                        .offset(x: position * 44)
                        .scaleEffect(1 - 0.1 * away)
                        .opacity(Double(max(0, 1 - away * 2)))
                        .allowsHitTesting(i == page)
                }
            }
            .frame(width: width, height: 188)
            .contentShape(Rectangle())
            .gesture(
                DragGesture(minimumDistance: 8)
                    .onChanged { value in
                        if sideways == nil { sideways = abs(value.translation.width) > abs(value.translation.height) }
                        guard sideways == true else { return }
                        var dx = value.translation.width
                        // Past either end it gives, but grudgingly.
                        if (page == 0 && dx > 0) || (page == count - 1 && dx < 0) { dx /= 3 }
                        drag = dx
                        head = CGFloat(page) + max(-1, min(1, -dx / width))
                    }
                    .onEnded { value in
                        defer { sideways = nil }
                        guard sideways == true else { return }
                        // Halfway across, or a flick either way, turns the page.
                        let speed = value.velocity.width
                        var next = page
                        if value.translation.width < -width * 0.5 || speed < -250 { next = min(count - 1, page + 1) }
                        if value.translation.width > width * 0.5 || speed > 250 { next = max(0, page - 1) }
                        if next != page { Haptics.select() }
                        // Carry on at the finger's speed into a stiff spring: quick, a hair of overshoot.
                        let remaining = (CGFloat(page - next) * width) - drag
                        let velocity = abs(remaining) > 1 ? Double(speed / remaining) : 0
                        withAnimation(.interpolatingSpring(stiffness: 420, damping: 34, initialVelocity: velocity)) {
                            page = next; drag = 0
                        }
                        withAnimation(.spring(response: 0.22, dampingFraction: 0.85)) { head = CGFloat(next) }
                        withAnimation(.spring(response: 0.34, dampingFraction: 0.8).delay(0.04)) { tail = CGFloat(next) }
                    }
            )
            dots
        }
        .onAppear { head = CGFloat(page); tail = CGFloat(page) }
    }

    /// Inactive dots, and over them one white capsule spanning from tail to head.
    private var dots: some View {
        let dot: CGFloat = 6, gap: CGFloat = 7, step = dot + gap
        return ZStack(alignment: .leading) {
            HStack(spacing: gap) {
                ForEach(0..<count, id: \.self) { _ in Circle().fill(V.outline).frame(width: dot, height: dot) }
            }
            Capsule().fill(V.text)
                .frame(width: dot + abs(head - tail) * step, height: dot)
                .offset(x: min(head, tail) * step)
        }
        .frame(height: dot)
        .accessibilityHidden(true)
    }
}

// MARK: - Heat control

/// Heat cabin, in one piece from tap to heating and back: the orange glass darkens into the
/// heating capsule, the flame turns into a spinner and then a breathing dot, the words slide
/// to the left and Stop grows in from the right. Every step is the same view, so it morphs.
struct HeatControl: View {
    enum Phase: Equatable { case idle, connecting, starting, running, stopping }
    let phase: Phase
    let minutesLeft: Int
    let canStart: Bool
    let start: () -> Void
    let stop: () -> Void
    @State private var sweep = false
    @State private var pulse = false

    private var active: Bool { phase != .idle }
    private static let morph = Animation.spring(duration: 0.55, bounce: 0.12)

    var body: some View {
        ZStack {
            Button(action: start) { surface }
                .buttonStyle(PressStyle())
                .disabled(active || !canStart)
            if active {
                stopButton
                    .frame(maxWidth: .infinity, alignment: .trailing)
                    .padding(.trailing, 10)
                    .transition(.asymmetric(
                        insertion: .scale(scale: 0.6, anchor: .trailing).combined(with: .opacity).animation(Self.morph.delay(0.08)),
                        removal: .scale(scale: 0.8, anchor: .trailing).combined(with: .opacity)))
            }
        }
        .frame(height: 60)
        .opacity(active || canStart ? 1 : 0.5)
        .animation(Self.morph, value: phase)
        .animation(.easeOut(duration: 0.25), value: canStart)
        .onChange(of: phase) { old, new in
            if new == .running, old != .running { Haptics.notify(.success) }
        }
        .onAppear {
            withAnimation(.timingCurve(0.4, 0, 0.2, 1, duration: 5.2).repeatForever(autoreverses: false)) { sweep = true }
            withAnimation(.timingCurve(0.45, 0, 0.55, 1, duration: 2.4).repeatForever(autoreverses: true)) { pulse = true }
        }
        .accessibilityElement(children: .contain)
    }

    private var surface: some View {
        ZStack {
            // Resting: frosted glass with an orange cast.
            Color.clear
                .glassCapsule(tint: V.climate.opacity(0.85))
                .overlay(GlassSheen())
                .opacity(active ? 0 : 1)
            // Working: the dark capsule with an orange edge; a light band drifts through while heating.
            ZStack {
                Capsule().fill(V.ground)
                Capsule().fill(V.activeFill(V.climate))
                GeometryReader { g in
                    LinearGradient(colors: [V.climate.opacity(0), V.climate.opacity(0.07), V.climateLight.opacity(0.12), V.climate.opacity(0.07), V.climate.opacity(0)],
                                   startPoint: .leading, endPoint: .trailing)
                        .frame(width: g.size.width * 0.55)
                        .offset(x: sweep ? g.size.width * 1.1 : -g.size.width * 0.6)
                        .opacity(sweep ? 0 : 1)
                }
                .clipShape(Capsule())
                .opacity(phase == .running ? 1 : 0)
                Capsule().strokeBorder(V.climate, lineWidth: 1.5)
            }
            .opacity(active ? 1 : 0)
            .scaleEffect(active ? 1 : 0.97)

            HStack(spacing: 10) {
                indicator.frame(width: 20, height: 20)
                label
            }
            // Dark on the white glass, white on the dark capsule.
            .foregroundStyle(active ? V.climate : V.ground)
            .frame(maxWidth: .infinity, alignment: active ? .leading : .center)
            .padding(.leading, active ? 22 : 0)
            // Room for Stop, so a long line shrinks rather than running under it.
            .padding(.trailing, active ? 100 : 0)
        }
        .frame(maxWidth: .infinity)
        .frame(height: 60)
        .contentShape(Capsule())
    }

    @ViewBuilder private var indicator: some View {
        switch phase {
        case .idle:
            PhIcon(name: "wind", size: 20).transition(.blurReplace.combined(with: .scale(0.6)))
        case .connecting, .starting, .stopping:
            ProgressView().controlSize(.small).tint(V.climate).transition(.blurReplace.combined(with: .scale(0.6)))
        case .running:
            Circle().fill(V.climate).frame(width: 10, height: 10)
                .scaleEffect(pulse ? 1.08 : 0.92).opacity(pulse ? 1 : 0.55)
                .transition(.blurReplace.combined(with: .scale(0.2)))
        }
    }

    private var label: some View {
        Group {
            switch phase {
            case .idle: Text("Climate")
            // Same words while sending and while the car answers, so nothing flickers in between.
            case .connecting, .starting: Text("Connecting to the car…")
            case .running:
                Text("Climate on · \(minutesLeft) min")
                    .contentTransition(.numericText(countsDown: true))
                    .animation(.snappy, value: minutesLeft)
            case .stopping: Text("Stopping…")
            }
        }
        .font(V.button)
        .lineLimit(1).minimumScaleFactor(0.8)
        .id(labelKey)
        .transition(.blurReplace)
    }

    private var labelKey: Int {
        switch phase {
        case .idle: 0
        case .connecting, .starting: 1
        case .running: 2
        case .stopping: 3
        }
    }

    private var stopButton: some View {
        Button(action: stop) {
            Text("Stop").font(V.body).foregroundStyle(V.ground)
                .padding(.horizontal, 16).frame(height: 44)
                .background(Capsule().fill(V.climate))
        }
        .buttonStyle(PressStyle())
        // Nothing to stop until the start command is with the car.
        .disabled(phase == .connecting || phase == .stopping)
        .opacity(phase == .connecting || phase == .stopping ? 0.5 : 1)
    }
}

// MARK: - Action tile

struct ActionTile: View {
    /// `alert`: something left open (the boot unlocked); red, and a tap closes it.
    enum State { case idle, active, alert, pending, unavailable }
    let icon: String
    let title: String
    /// What it says while the car works on it.
    var busyTitle: String? = nil
    let state: State
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            VStack(spacing: 8) {
                ZStack {
                    if state == .pending {
                        ProgressView().tint(V.text).transition(.blurReplace.combined(with: .scale(0.6)))
                    } else {
                        PhIcon(name: icon, size: 26).transition(.blurReplace.combined(with: .scale(0.6)))
                    }
                }
                .frame(width: 26, height: 26)
                Text(state == .pending ? busyTitle ?? title : title)
                    .font(V.sora(14)).lineLimit(1).minimumScaleFactor(0.8)
                    .contentTransition(.opacity)
            }
            .padding(.horizontal, 4)
            .foregroundStyle(state == .active ? V.amber : state == .alert ? V.danger : state == .pending ? V.textMuted : state == .unavailable ? V.textFaint : V.text)
            .animation(.spring(duration: 0.4, bounce: 0.1), value: state)
            .frame(maxWidth: .infinity).frame(height: 78)
            .glassTile(tint: state == .active ? V.amber : state == .alert ? V.danger : nil)
            .contentShape(RoundedRectangle(cornerRadius: V.radiusCard, style: .continuous))
        }
        .buttonStyle(.plain)
        .disabled(state == .pending || state == .unavailable)
    }
}

// MARK: - Unlock slider

/// A 60 pt track with a white knob; drag it to the far end to unlock (or lock). The knob is
/// white whatever the state; the state reads in the status line.
/// A switch you slide: the knob rests left while the car is locked (white) and right while it's
/// unlocked (red), so where it sits is the car's state. Slide it across to change it; the colour
/// follows the knob, and a finished slide holds there until the car answers.
struct UnlockSlider: View {
    let locked: Bool
    /// While a command is on its way to the car: true when unlocking, false when locking.
    let pending: Bool?
    let busy: Bool
    /// While the unlock question is up: the knob stays where the slide left it.
    var holding = false
    let onComplete: (_ unlock: Bool) -> Void
    /// How far the finger has moved the knob from where it rests.
    @State private var drag: CGFloat = 0
    /// After a completed slide, the state it's heading for, held until the car answers.
    @State private var heading: Bool?
    /// Live copy of "a question or a command is under way", for the timer below to read.
    @State private var waiting = false

    var body: some View {
        GeometryReader { g in
            let travel = g.size.width - 50 - 10
            // Where the knob rests: by the state it's heading for, else the car's.
            let unlockedSide = heading ?? pending ?? !locked
            let rest: CGFloat = unlockedSide ? travel : 0
            let position = min(travel, max(0, rest + drag))
            let red = travel > 0 ? position / travel : 0
            let away = travel > 0 ? abs(position - rest) / travel : 0
            ZStack(alignment: .leading) {
                Color.clear.glassCapsule(tint: nil)
                    .overlay(Capsule().strokeBorder(V.danger.opacity(0.7 * red), lineWidth: 1.5))
                    .background(Capsule().fill(V.danger.opacity(0.10 * red)))
                    .shadow(color: V.danger.opacity(0.35 * red), radius: 14)
                ZStack {
                    if let pending {
                        // Waiting for the car: what it's doing, with a light running through it.
                        ShimmerText(text: pending ? "UNLOCKING" : "LOCKING", color: pending ? V.danger : V.text)
                            .transition(.blurReplace)
                    } else {
                        ZStack {
                            Text("SWIPE TO UNLOCK").foregroundStyle(V.textMuted).opacity(unlockedSide ? 0 : 1)
                            Text("SWIPE TO LOCK").foregroundStyle(V.danger).opacity(unlockedSide ? 1 : 0)
                        }
                        .transition(.blurReplace)
                    }
                }
                .font(V.eyebrow).tracking(3)
                // The words sit in the space the knob isn't in.
                .frame(maxWidth: .infinity)
                .padding(.leading, unlockedSide ? 0 : 50).padding(.trailing, unlockedSide ? 50 : 0)
                .opacity(1 - Double(away) * 1.6)
                ZStack {
                    if pending != nil {
                        ProgressView().controlSize(.small).tint(V.ground)
                            .transition(.blurReplace.combined(with: .scale(0.6)))
                    } else {
                        ZStack {
                            PhIcon(name: "lock", size: 20).opacity(red < 0.5 ? 1 : 0)
                            PhIcon(name: "lock-open", size: 20).opacity(red < 0.5 ? 0 : 1)
                        }
                        .transition(.blurReplace.combined(with: .scale(0.6)))
                    }
                }
                .foregroundStyle(V.ground)
                .animation(.easeOut(duration: 0.15), value: red < 0.5)
                .frame(width: 50, height: 50)
                // The same frosted treatment as Heat cabin, its colour mixed white→red with the knob.
                .glassCapsule(tint: Self.mix(red))
                .background(Capsule().fill(Self.mix(red)))
                .overlay(GlassSheen())
                .offset(x: 5 + position)
                .gesture(DragGesture()
                    .onChanged { value in
                        guard heading == nil else { return }
                        drag = value.translation.width
                    }
                    .onEnded { _ in
                        guard heading == nil else { return }
                        let end = min(travel, max(0, rest + drag))
                        let done = locked ? end >= travel * 0.85 : end <= travel * 0.15
                        if done {
                            Haptics.notify(.success)
                            withAnimation(.spring(response: 0.3, dampingFraction: 0.85)) { heading = locked; drag = 0 }
                            onComplete(locked)
                            // If nothing comes of it (the question was cancelled), go back: once
                            // nothing is under way, and still nothing a moment later.
                            Task {
                                try? await Task.sleep(for: .seconds(1))
                                while true {
                                    while waiting { try? await Task.sleep(for: .milliseconds(250)) }
                                    try? await Task.sleep(for: .milliseconds(600))
                                    if !waiting { break }
                                }
                                if heading != nil { withAnimation(.spring(response: 0.45, dampingFraction: 0.8)) { heading = nil } }
                            }
                        } else {
                            withAnimation(.spring(response: 0.35, dampingFraction: 0.8)) { drag = 0 }
                        }
                    })
            }
        }
        .frame(height: 60)
        // Its own command isn't dimmed (the spinner says what's happening); others' are.
        .opacity(busy && pending == nil ? 0.75 : 1)
        .disabled(busy)
        .animation(.spring(duration: 0.45, bounce: 0.1), value: pending)
        .onChange(of: holding || pending != nil, initial: true) { _, now in waiting = now }
        .onChange(of: locked) { _, _ in withAnimation(.spring(response: 0.45, dampingFraction: 0.8)) { heading = nil } }
        .onChange(of: busy) { _, isBusy in
            if !isBusy { withAnimation(.spring(response: 0.45, dampingFraction: 0.8)) { heading = nil } }
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(locked ? "Locked. Unlock" : "Unlocked. Lock")
        .accessibilityAddTraits(.isButton)
        .accessibilityAction { onComplete(locked) }
    }

    /// The label while the car works on it, a soft light running through the letters.
    struct ShimmerText: View {
        let text: String
        let color: Color
        @State private var run = false

        var body: some View {
            Text(text).foregroundStyle(color.opacity(0.7))
                .overlay {
                    GeometryReader { g in
                        LinearGradient(colors: [.clear, .white, .clear], startPoint: .leading, endPoint: .trailing)
                            .frame(width: g.size.width * 0.5)
                            .offset(x: run ? g.size.width * 1.1 : -g.size.width * 0.6)
                    }
                    .mask(Text(text))
                    .blendMode(.plusLighter)
                }
                .onAppear {
                    withAnimation(.easeInOut(duration: 1.3).repeatForever(autoreverses: false)) { run = true }
                }
        }
    }

    /// White (zinc-100) at 0 to red (red-400) at 1.
    static func mix(_ t: CGFloat) -> Color {
        let t = Double(min(1, max(0, t)))
        func lerp(_ a: Double, _ b: Double) -> Double { (a + (b - a) * t) / 255 }
        return Color(red: lerp(244, 248), green: lerp(244, 113), blue: lerp(245, 113))
    }
}

// MARK: - Toast item

struct ToastItem: Equatable {
    let id = UUID()
    let title: String
    var detail: String? = nil
    var isError = false

    /// Below this, unplugged, a refused heat is most likely the car saving its charge for driving.
    static let lowForHeating = 30.0

    init?(_ state: CarModel.CommandState, status: VehicleStatus? = nil) {
        switch state {
        case .idle, .sending, .waitingForCar:
            return nil
        case .failed(let message):
            title = "Couldn't reach the car"; detail = message; isError = true
        case .done(.preconditionOn, .failed, _)
            where status?.isPluggedIn != true && (status?.stateOfCharge ?? 100) < Self.lowForHeating:
            title = "Battery may be too low"; detail = "Plug in and try again."; isError = true
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
        .preconditionOn: "Climate on", .preconditionOff: "Climate off", .lock: "Locked", .unlock: "Unlocked",
        .lights: "Lights flashed", .trunkUnlock: "Boot unlocked", .trunkLock: "Boot locked",
        .liftgateUnlock: "Liftgate unlocked", .liftgateLock: "Liftgate locked", .hornLights: "Horn and lights", .chargeNow: "Charging started",
        .deepRefresh: "Updated from the car", .locate: "Location updated",
    ]
    private static let sent: [RemoteCommand: String] = [
        .preconditionOn: "Climate sent", .preconditionOff: "Stop sent", .lock: "Lock sent", .unlock: "Unlock sent",
        .lights: "Lights sent", .trunkUnlock: "Boot unlock sent", .trunkLock: "Boot lock sent",
        .liftgateUnlock: "Liftgate unlock sent", .liftgateLock: "Liftgate lock sent", .hornLights: "Horn sent", .chargeNow: "Charge now sent",
        .deepRefresh: "Update requested", .locate: "Location requested",
    ]
}
