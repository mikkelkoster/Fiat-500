import ActivityKit
import Foundation
import CoreLocation
import WeatherKit
import Observation
import SwiftUI
import WidgetKit

/// App state shared by the UI, App Intents (Siri/Shortcuts), notification actions and
/// background refresh — one instance so they all see the same car and command state.
@MainActor
@Observable
final class CarModel {
    static let shared = CarModel()

    enum CommandState: Equatable {
        case idle
        case sending(RemoteCommand)
        case waitingForCar(RemoteCommand)
        case done(RemoteCommand, OperationResult, Date)
        case failed(String)
    }

    /// Whether the car offers a command and whether the account has it switched on.
    enum Availability { case available, needsSubscription, unsupported }

    private(set) var hasAccount = false
    private(set) var vehicles: [Vehicle] = []
    private(set) var status: VehicleStatus?
    private(set) var commandState: CommandState = .idle
    /// Bumped per command, so a wait that was overtaken by a newer command (Stop while starting) stays quiet.
    private var commandID = 0
    private var pendingWait: Task<OperationResult, Never>?
    private(set) var lastPreheatStart: Date?
    private(set) var statusError: String?
    private(set) var location: CarLocation?
    private(set) var locationError: String?

    var selectedVIN: String? {
        didSet {
            defaults.set(selectedVIN, forKey: Keys.vin)
            if oldValue != selectedVIN { loadCarSettings() }
        }
    }
    // Name, plate and colour belong to the car, so each car on the account keeps its own.
    var plate: String {
        didSet { defaults.set(plate, forKey: carKey(Keys.plate)) }
    }
    var carName: String {
        didSet { defaults.set(carName, forKey: carKey(Keys.carName)) }
    }
    /// The longest range a full charge has given this car, learned from status reads, so the range
    /// gauge can show this charge against the car's best (cold weather shortens the arc).
    var bestFullRangeKm: Double? {
        get { selectedVIN.flatMap { defaults.object(forKey: "bestFullRange.\($0)") as? Double } }
        set { if let vin = selectedVIN { defaults.set(newValue, forKey: "bestFullRange.\(vin)") } }
    }

    /// Range left in km, from the status in whatever unit Fiat sent.
    var rangeKm: Double? {
        // The battery's range where there is one; otherwise the tank's.
        if var km = status?.range {
            if status?.rangeUnit?.lowercased().hasPrefix("mi") == true { km *= 1.609 }
            return km
        }
        guard var km = status?.fuelRange else { return nil }
        if status?.fuelRangeUnit?.lowercased().hasPrefix("mi") == true { km *= 1.609 }
        return km
    }

    /// Range as a share of the best full-charge range seen; falls back to the battery level.
    var rangeFraction: Double {
        guard let km = rangeKm, let soc = status?.stateOfCharge, soc > 0 else {
            return (status?.stateOfCharge ?? status?.fuelLevel ?? 0) / 100
        }
        let full = max(bestFullRangeKm ?? 0, km * 100 / soc)
        return full > 0 ? min(1, km / full) : soc / 100
    }
    var ownerName: String? {
        didSet { defaults.set(ownerName, forKey: Keys.ownerName) }
    }
    var useMiles: Bool {
        didSet { defaults.set(useMiles, forKey: Keys.useMiles) }
    }
    private(set) var onboarded: Bool {
        didSet { defaults.set(onboarded, forKey: Keys.onboarded) }
    }
    var schedules: [PreheatSchedule] {
        didSet {
            // The sample car's schedules are pretend: nothing saved, nothing scheduled.
            guard !Demo.isActive else { return }
            defaults.set(try? JSONEncoder().encode(schedules), forKey: Keys.schedules)
            ScheduleCoordinator.shared.reschedule(schedules)
        }
    }

    /// The 500e stops preconditioning on its own; treat it as running for this long.
    static let assumedPreheatDuration: TimeInterval = 30 * 60

    var isPreheating: Bool {
        guard let lastPreheatStart else { return false }
        return Date().timeIntervalSince(lastPreheatStart) < Self.assumedPreheatDuration
    }

    var preheatMinutesLeft: Int {
        guard let lastPreheatStart else { return 0 }
        return max(0, Int((Self.assumedPreheatDuration - Date().timeIntervalSince(lastPreheatStart)) / 60))
    }


    var isBusy: Bool {
        switch commandState {
        case .sending, .waitingForCar: true
        default: false
        }
    }

    var vehicle: Vehicle? { vehicles.first { $0.vin == selectedVIN } }

    /// The schedule that runs next and when the car will be warm, for the home screen and widgets.
    var nextSchedule: (schedule: PreheatSchedule, ready: Date)? {
        schedules.compactMap { s in
            s.upcomingStarts(after: Date()).first.map { (s, $0.addingTimeInterval(TimeInterval(s.leadMinutes * 60))) }
        }
        .min { $0.1 < $1.1 }
    }

    /// From the car's service list. A car that lists nothing gets every command, so an older or
    /// different account isn't locked out by a list it doesn't send.
    private func lists(_ command: RemoteCommand) -> Bool { vehicle?.services.contains(command.rawValue) == true }

    /// Boot or liftgate, whichever the car lists (boot when it lists neither, or nothing at all).
    var bootUnlockCommand: RemoteCommand {
        !lists(.trunkUnlock) && lists(.liftgateUnlock) ? .liftgateUnlock : .trunkUnlock
    }

    /// What locks the boot again: its own command where the car lists it, else locking the car.
    var bootLockCommand: RemoteCommand {
        if bootUnlockCommand == .liftgateUnlock { return lists(.liftgateLock) ? .liftgateLock : .lock }
        return lists(.trunkLock) ? .trunkLock : .lock
    }

    /// Lights alone where the car offers it; horn and lights where that's all it offers.
    var findCommand: RemoteCommand {
        !lists(.lights) && lists(.hornLights) ? .hornLights : .lights
    }

    func availability(of command: RemoteCommand) -> Availability {
        guard let vehicle, !vehicle.services.isEmpty || !vehicle.disabledServices.isEmpty else { return .available }
        if vehicle.services.contains(command.rawValue) { return .available }
        if vehicle.disabledServices.contains(command.rawValue) { return .needsSubscription }
        return .unsupported
    }

    private let client = UconnectClient()
    private let defaults = UserDefaults.standard

    private enum Keys {
        static let vin = "selectedVIN"
        static let vehicles = "vehicles"
        static let plate = "plate"
        static let carName = "carName"
        static let carColor = "carColor"
        static let ownerName = "ownerName"
        static let useMiles = "useMiles"
        static let onboarded = "onboarded"
        static let schedules = "schedules"
        static let lastPreheat = "lastPreheatStart"
    }

    private func carKey(_ base: String) -> String {
        selectedVIN.map { "\(base).\($0)" } ?? base
    }

    /// The selected car's name, plate and colour; a car seen for the first time takes its
    /// nickname or model.
    private func loadCarSettings() {
        plate = defaults.string(forKey: carKey(Keys.plate)) ?? ""
        carName = defaults.string(forKey: carKey(Keys.carName)) ?? vehicle.map { $0.nickname ?? $0.model ?? "My car" } ?? "My car"
        location = nil
        status = Self.savedStatus(selectedVIN, defaults)
    }

    /// The last numbers read for a car, shown (with their time) until fresh ones arrive.
    private static func savedStatus(_ vin: String?, _ defaults: UserDefaults) -> VehicleStatus? {
        guard let vin, let data = defaults.data(forKey: "status.\(vin)") else { return nil }
        return try? JSONDecoder().decode(VehicleStatus.self, from: data)
    }

    private init() {
        let savedVIN = defaults.string(forKey: Keys.vin)
        // Last launch's car list: what the car can do is known before Fiat answers.
        vehicles = defaults.data(forKey: Keys.vehicles).flatMap { try? JSONDecoder().decode([Vehicle].self, from: $0) } ?? []
        selectedVIN = savedVIN
        // Settings saved before they were kept per car move to the selected car.
        if let vin = savedVIN {
            for key in [Keys.plate, Keys.carName, Keys.carColor] where defaults.object(forKey: "\(key).\(vin)") == nil {
                if let old = defaults.string(forKey: key) { defaults.set(old, forKey: "\(key).\(vin)") }
            }
        }
        plate = ""
        carName = "My car"
        ownerName = defaults.string(forKey: Keys.ownerName)
        useMiles = defaults.bool(forKey: Keys.useMiles)
        onboarded = defaults.bool(forKey: Keys.onboarded)
        schedules = defaults.data(forKey: Keys.schedules)
            .flatMap { try? JSONDecoder().decode([PreheatSchedule].self, from: $0) } ?? []
        lastPreheatStart = defaults.object(forKey: Keys.lastPreheat) as? Date

        hasAccount = AccountStore.load() != nil
        plate = defaults.string(forKey: carKey(Keys.plate)) ?? ""
        carName = defaults.string(forKey: carKey(Keys.carName)) ?? "My car"
        status = Self.savedStatus(selectedVIN, defaults)

        if Demo.isActive { loadSample() }
    }

    /// The made-up 500e, with its numbers, schedules and position.
    private func loadSample() {
        hasAccount = true
        onboarded = Demo.screen != "onboarding"
        vehicles = Demo.vehicles
        selectedVIN = Demo.vehicle.vin
        // The sample is no particular car; the screenshot demo keeps its 500e.
        plate = Demo.isSample ? "VARME" : "ED 35079"
        carName = UserDefaults.standard.string(forKey: "demoName") ?? (Demo.isSample ? "Sample car" : "Fiat 500e")
        status = UserDefaults.standard.bool(forKey: "demoLoading") ? nil : Demo.status
        defaults.set(300.0, forKey: "bestFullRange.\(Demo.vehicle.vin)")
        schedules = Demo.schedules
        location = Demo.location
        lastPreheatStart = Demo.screen == "preheating" ? Date().addingTimeInterval(-6 * 60) : nil
    }

    /// "Try with a sample car": the whole app on pretend data, nothing sent anywhere.
    func startSampleCar() {
        defaults.set(true, forKey: Demo.sampleKey)
        loadSample()
        onboarded = true
    }

    // MARK: Account

    var account: UconnectAccount? { Demo.isActive ? Demo.account : AccountStore.load() }

    /// Saves the account and verifies it by fetching the vehicle list.
    func signIn(_ account: UconnectAccount) async throws {
        await client.setAccount(account)
        let found = try await client.vehicles()
        AccountStore.save(account)
        hasAccount = true
        vehicles = found
        defaults.set(try? JSONEncoder().encode(found), forKey: Keys.vehicles)
        if selectedVIN == nil || !found.contains(where: { $0.vin == selectedVIN }) {
            selectedVIN = found.first?.vin
        }
        if ownerName == nil, let first = await client.ownerFirstName { ownerName = first }
        if carName == "My car", let v = vehicle { carName = v.nickname ?? v.model ?? carName }
        if defaults.object(forKey: Keys.useMiles) == nil, account.region == .northAmerica { useMiles = true }
        await refreshStatus()
    }

    func finishOnboarding() {
        onboarded = true
    }

    func signOut() async {
        if Demo.isSample {
            // Back to the welcome screen with the owner's own things as they were.
            defaults.removeObject(forKey: Demo.sampleKey)
            hasAccount = false
            onboarded = false
            vehicles = []
            status = nil
            location = nil
            lastPreheatStart = nil
            selectedVIN = nil
            schedules = defaults.data(forKey: Keys.schedules).flatMap { try? JSONDecoder().decode([PreheatSchedule].self, from: $0) } ?? []
            return
        }
        AccountStore.delete()
        await client.setAccount(nil)
        hasAccount = false
        onboarded = false
        vehicles = []
        defaults.removeObject(forKey: Keys.vehicles)
        for key in defaults.dictionaryRepresentation().keys where key.hasPrefix("status.") { defaults.removeObject(forKey: key) }
        status = nil
        location = nil
        selectedVIN = nil
    }

    // MARK: Status

    func refreshStatus() async {
        guard hasAccount else { return }
        if Demo.isActive {
            status = Demo.status
            return
        }
        await client.setAccount(account)
        // Fiat can be slow, but not this slow: past 40 s it's stuck, and saying so beats waiting.
        let watchdog = Task { [weak self] in
            try await Task.sleep(for: .seconds(40))
            self?.statusError = "Fiat didn't answer. Pull down to try again."
        }
        defer { watchdog.cancel() }
        do {
            // Fetched every time: the service list changes when a brand subscription starts or ends.
            vehicles = try await client.vehicles()
            defaults.set(try? JSONEncoder().encode(vehicles), forKey: Keys.vehicles)
            if selectedVIN == nil || vehicle == nil { selectedVIN = vehicles.first?.vin }
            guard let vin = selectedVIN else { return }
            let fresh = try await client.status(vin: vin)
            status = fresh
            defaults.set(try? JSONEncoder().encode(fresh), forKey: "status.\(vin)")
            statusError = nil
            learnFullRange()
            CarAlerts.evaluate(fresh, carName: carName, rangeText: rangeText(fresh))
        } catch {
            statusError = error.localizedDescription
        }
        publishSnapshot()
    }

    /// Above 30 % the projection to a full charge is steady enough to learn from.
    private func learnFullRange() {
        guard let km = rangeKm, let soc = status?.stateOfCharge, soc >= 30 else { return }
        let full = km * 100 / soc
        if full > (bestFullRangeKm ?? 0) { bestFullRangeKm = full }
    }

    /// The car's own report is older than this, so a refresh should wake it.
    var isStale: Bool {
        guard let reported = status?.reportedAt ?? status?.updatedAt else { return true }
        return Date().timeIntervalSince(reported) > 30 * 60
    }

    private func rangeText(_ status: VehicleStatus) -> String {
        guard var km = status.range else { return "–" }
        if status.rangeUnit?.lowercased().hasPrefix("mi") == true { km *= 1.609 }
        return useMiles ? "\(Int(km / 1.609)) mi" : "\(Int(km)) km"
    }

    /// Asks the car itself for fresh numbers, in the background: no message, no busy buttons,
    /// and if the car doesn't answer, the numbers already shown stay.
    func wakeQuietly() async {
        guard hasAccount, !Demo.isActive, let vin = selectedVIN,
              availability(of: .deepRefresh) == .available, wakeState != .waking,
              !wakeRefused(vin) else { return }
        wakeState = .waking
        await client.setAccount(account)
        do {
            let id = try await client.send(.deepRefresh, vin: vin)
            if await client.waitForResult(vin: vin, correlationId: id) == .succeeded {
                await refreshStatus()
                wakeState = .idle
                return
            }
            wakeState = .failed("The car didn't answer")
        } catch UconnectError.requestFailed(403, _) {
            // Fiat won't wake this car on request (seen on a 2022 500e with My Remote). Don't ask
            // again on every pull; try once more after a week in case that changes.
            defaults.set(Date(), forKey: "wakeRefused.\(vin)")
            wakeState = .failed("Can't wake this car remotely")
        } catch {
            wakeState = .failed(Self.shortReason(error))
        }
        // The note stays a while, then the line goes back to the car's last report.
        try? await Task.sleep(for: .seconds(8))
        if case .failed = wakeState { wakeState = .idle }
    }

    private func wakeRefused(_ vin: String) -> Bool {
        guard let when = defaults.object(forKey: "wakeRefused.\(vin)") as? Date else { return false }
        return Date().timeIntervalSince(when) < 7 * 86_400
    }

    enum WakeState: Equatable { case idle, waking, failed(String) }
    /// Asking the car for fresh numbers: the header says so, and says if it came to nothing.
    private(set) var wakeState: WakeState = .idle

    private static func shortReason(_ error: Error) -> String {
        if case UconnectError.requestFailed(let code, _) = error { return "Fiat refused (\(code))" }
        return "Couldn't reach Fiat"
    }

    // MARK: Cars

    /// The name given to another car on the account, for the switcher.
    func savedName(for vehicle: Vehicle) -> String? {
        defaults.string(forKey: "\(Keys.carName).\(vehicle.vin)")
    }

    /// Shows another car on the account.
    func switchCar(to vin: String) async {
        guard vin != selectedVIN else { return }
        selectedVIN = vin
        if Demo.isActive { status = Demo.status; return }
        await refreshStatus()
        await loadLocation()
    }

    // MARK: Trips

    func loadTrips() async throws -> [Trip] {
        guard hasAccount, let vin = selectedVIN else { return [] }
        if Demo.isActive { return Demo.trips }
        await client.setAccount(account)
        let reply = try await client.trips(vin: vin)
        lastTripsReply = (try? JSONSerialization.data(withJSONObject: reply, options: [.prettyPrinted, .sortedKeys]))
            .map { String(decoding: $0, as: UTF8.self) }
        return Trip.list(from: reply)
    }

    // MARK: Temperature

    /// Outside at the car from Apple Weather, for cars that don't report it themselves.
    private(set) var weatherTemperature: Double?
    private var weatherFetchedAt: Date?
    /// Apple's mark and legal link, shown in Settings whenever Apple Weather supplied the number.
    private(set) var weatherAttribution: WeatherAttribution?

    /// Outside the car in °C: the car's own reading, else Apple Weather at its last position.
    var outsideTemperature: Double? { status?.outsideTemperature ?? weatherTemperature }

    /// Looks up the weather where the car is parked, at most every 15 minutes.
    func loadWeather() async {
        if Demo.isActive {
            weatherTemperature = UserDefaults.standard.string(forKey: "demoOutside").flatMap(Double.init) ?? 3
            return
        }
        guard status?.outsideTemperature == nil, let location,
              Date().timeIntervalSince(weatherFetchedAt ?? .distantPast) > 15 * 60 else { return }
        do {
            let current = try await WeatherService.shared.weather(
                for: CLLocation(latitude: location.latitude, longitude: location.longitude), including: .current)
            weatherTemperature = current.temperature.converted(to: .celsius).value
            weatherFetchedAt = Date()
            if weatherAttribution == nil { weatherAttribution = try? await WeatherService.shared.attribution }
        } catch {
            // No weather (offline, or the service not switched on): the hint just doesn't show.
        }
    }

    /// Everything Fiat says about the car, for the owner to copy and share when something's missing.
    func carReport() async -> String? {
        guard hasAccount, !Demo.isActive, let vin = selectedVIN else { return nil }
        await client.setAccount(account)
        guard let raw = try? await client.rawStatus(vin: vin) else { return nil }
        guard let data = try? JSONSerialization.data(withJSONObject: raw, options: [.prettyPrinted, .sortedKeys]) else { return nil }
        return String(decoding: data, as: UTF8.self)
    }

    /// Fiat's trips reply as it came, for the owner to copy when the app can't read part of it.
    private(set) var lastTripsReply: String?

    // MARK: Location

    /// Reads where the car last reported itself, without waking it.
    func loadLocation() async {
        guard hasAccount, !Demo.isActive, let vin = selectedVIN else { return }
        await client.setAccount(account)
        do {
            location = try await client.location(vin: vin)
            locationError = nil
        } catch {
            locationError = error.localizedDescription
        }
    }

    // MARK: Schedules

    func saveSchedule(_ schedule: PreheatSchedule) {
        if let index = schedules.firstIndex(where: { $0.id == schedule.id }) {
            schedules[index] = schedule
        } else {
            schedules.append(schedule)
        }
        publishSnapshot()
    }

    func deleteSchedule(_ id: PreheatSchedule.ID) {
        schedules.removeAll { $0.id == id }
        publishSnapshot()
    }

    /// Fired by a notification or background refresh for one schedule: honours its "only when plugged in".
    func scheduledPreheat(scheduleID: PreheatSchedule.ID?) async {
        let schedule = schedules.first { $0.id == scheduleID }
        if schedule?.onlyWhenPluggedIn ?? true {
            await refreshStatus()
            if status?.isPluggedIn == false { return }
        }
        await startPreheat(waitForCar: false)
    }

    // MARK: Commands

    @discardableResult
    func startPreheat(waitForCar: Bool = true) async -> CommandState {
        await run(.preconditionOn, waitForCar: waitForCar)
    }

    @discardableResult
    func stopPreheat(waitForCar: Bool = true) async -> CommandState {
        await run(.preconditionOff, waitForCar: waitForCar)
    }

    /// Sends any remote command and, unless told not to, waits for the car to confirm it.
    @discardableResult
    func perform(_ command: RemoteCommand, waitForCar: Bool = true) async -> CommandState {
        await run(command, waitForCar: waitForCar)
    }

    private func run(_ command: RemoteCommand, waitForCar: Bool) async -> CommandState {
        guard hasAccount, let vin = selectedVIN else {
            commandState = .failed(UconnectError.missingAccount.localizedDescription)
            return commandState
        }
        pendingWait?.cancel()
        commandID += 1
        let id = commandID
        commandState = .sending(command)
        if Demo.isActive {
            try? await Task.sleep(for: .seconds(1))
            recordAccepted(command)
            if waitForCar {
                commandState = .waitingForCar(command)
                let wait = Task { () -> OperationResult in
                    try? await Task.sleep(for: .seconds(4))
                    return Task.isCancelled ? .unknown : .succeeded
                }
                pendingWait = wait
                _ = await wait.value
                guard id == commandID else { return .done(command, .unknown, Date()) }
            }
            await followUp(command)
            commandState = .done(command, .succeeded, Date())
            return commandState
        }
        await client.setAccount(account)
        do {
            let correlationId = try await client.send(command, vin: vin)
            recordAccepted(command)
            guard waitForCar else {
                commandState = .done(command, .unknown, Date())
                return commandState
            }
            commandState = .waitingForCar(command)
            let wait = Task { [client] in await client.waitForResult(vin: vin, correlationId: correlationId) }
            pendingWait = wait
            let result = await wait.value
            guard id == commandID else { return .done(command, result, Date()) }
            if result == .failed, command == .preconditionOn { setLastPreheat(nil) }
            if result == .succeeded { await followUp(command) }
            commandState = .done(command, result, Date())
        } catch {
            if id == commandID { commandState = .failed(error.localizedDescription) }
        }
        return commandState
    }

    private func recordAccepted(_ command: RemoteCommand) {
        switch command {
        case .preconditionOn: setLastPreheat(Date())
        case .preconditionOff: setLastPreheat(nil)
        default: break
        }
    }

    /// Reads back what a confirmed command changed, so the screen shows the car's new state.
    private func followUp(_ command: RemoteCommand) async {
        switch command {
        // Central locking takes the boot with it.
        case .lock: status?.isLocked = true; status?.isTrunkLocked = true; publishSnapshot()
        case .trunkLock, .liftgateLock: status?.isTrunkLocked = true
        case .liftgateUnlock: status?.isTrunkLocked = false
        case .unlock: status?.isLocked = false; publishSnapshot()
        case .trunkUnlock: status?.isTrunkLocked = false
        case .locate: await loadLocation()
        case .deepRefresh, .chargeNow: await refreshStatus()
        default: break
        }
    }

    private func setLastPreheat(_ date: Date?) {
        lastPreheatStart = date
        guard !Demo.isActive else { return }
        defaults.set(date, forKey: Keys.lastPreheat)
        if let date { PreheatActivity.start(model: self, startedAt: date) } else { PreheatActivity.end() }
        publishSnapshot()
    }

    // MARK: Widgets

    /// What the widgets show. Written after every refresh and command.
    func publishSnapshot() {
        guard !Demo.isActive else { return }
        var rangeKm = status?.range
        if let r = rangeKm, status?.rangeUnit?.lowercased().hasPrefix("mi") == true { rangeKm = r * 1.609 }
        let next = nextSchedule?.ready.formatted(.dateTime.weekday(.abbreviated).hour().minute())
        CarSnapshot(carName: carName, plate: plate, stateOfCharge: status?.stateOfCharge, rangeKm: rangeKm, useMiles: useMiles,
                    isCharging: status?.isCharging == true, isPluggedIn: status?.isPluggedIn == true, isLocked: status?.isLocked,
                    preheatStartedAt: isPreheating ? lastPreheatStart : nil, nextSchedule: next, hasCarImage: false,
                    updatedAt: Date()).save()
        if let snapshot = CarSnapshot.load() { WatchLink.shared.publish(snapshot) }
        WidgetCenter.shared.reloadAllTimelines()
        if #available(iOS 18.0, *) { ControlCenter.shared.reloadAllControls() }
    }

    /// A widget or the Live Activity opened the app with a command.
    func handle(_ url: URL) {
        guard url.scheme == "varme", hasAccount else { return }
        switch url.host {
        case "preheat": Task { await startPreheat() }
        case "stop": Task { await stopPreheat() }
        case "lock": Task { await perform(.lock) }
        case "unlock": Task { await perform(.unlock) }
        case "find": pendingSheet = "find"
        default: break
        }
    }

    /// A sheet the home screen should open next (from a deep link).
    var pendingSheet: String?
}

/// The preheat Live Activity: starts when the car accepts the command, ends when it stops.
@MainActor
enum PreheatActivity {
    static func start(model: CarModel, startedAt: Date) {
        guard ActivityAuthorizationInfo().areActivitiesEnabled else { return }
        end()
        let end = startedAt.addingTimeInterval(CarModel.assumedPreheatDuration)
        let state = PreheatActivityAttributes.ContentState(
            endDate: end,
            warmBy: end.formatted(date: .omitted, time: .shortened),
            stateOfCharge: model.status?.stateOfCharge.map { Int($0) },
            rangeText: model.status?.range.map { "\(Int($0)) \(model.status?.rangeUnit?.lowercased() ?? "km")" }
        )
        let attributes = PreheatActivityAttributes(carName: model.carName, plate: model.plate)
        _ = try? Activity.request(attributes: attributes, content: .init(state: state, staleDate: end), pushType: nil)
    }

    static func end() {
        for activity in Activity<PreheatActivityAttributes>.activities {
            Task { await activity.end(nil, dismissalPolicy: .immediate) }
        }
    }
}
