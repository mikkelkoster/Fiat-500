import ActivityKit
import Foundation
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
    private(set) var lastPreheatStart: Date?
    private(set) var lastLightsOn: Date?
    private(set) var statusError: String?
    private(set) var location: CarLocation?
    private(set) var locationError: String?

    var selectedVIN: String? {
        didSet { defaults.set(selectedVIN, forKey: Keys.vin) }
    }
    var plate: String {
        didSet { defaults.set(plate, forKey: Keys.plate) }
    }
    var carName: String {
        didSet { defaults.set(carName, forKey: Keys.carName) }
    }
    /// The owner's own choice, as `#rrggbb`; tints the light around the car.
    var carColorHex: String {
        didSet { defaults.set(carColorHex, forKey: Keys.carColor) }
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
            defaults.set(try? JSONEncoder().encode(schedules), forKey: Keys.schedules)
            ScheduleCoordinator.shared.reschedule(schedules)
        }
    }

    /// The 500e stops preconditioning on its own; treat it as running for this long.
    static let assumedPreheatDuration: TimeInterval = 30 * 60
    /// The lights stay on about this long after the command.
    static let assumedLightsDuration: TimeInterval = 30

    var isPreheating: Bool {
        guard let lastPreheatStart else { return false }
        return Date().timeIntervalSince(lastPreheatStart) < Self.assumedPreheatDuration
    }

    var preheatMinutesLeft: Int {
        guard let lastPreheatStart else { return 0 }
        return max(0, Int((Self.assumedPreheatDuration - Date().timeIntervalSince(lastPreheatStart)) / 60))
    }

    var isLightsOn: Bool {
        guard let lastLightsOn else { return false }
        return Date().timeIntervalSince(lastLightsOn) < Self.assumedLightsDuration
    }

    var isBusy: Bool {
        switch commandState {
        case .sending, .waitingForCar: true
        default: false
        }
    }

    var vehicle: Vehicle? { vehicles.first { $0.vin == selectedVIN } }

    /// The one schedule the home screen shows and the sheet edits.
    var schedule: PreheatSchedule? { schedules.first }

    /// The picture of the car. For now the one render we have; other cars get a silhouette.
    var carImage: Image? {
        guard let vehicle else { return Demo.isActive ? Image("car-fiat-500e-nero") : nil }
        let isNew500 = vehicle.vin.hasPrefix("ZFAEFAC") || (vehicle.model ?? "").localizedCaseInsensitiveContains("500")
        return isNew500 ? Image("car-fiat-500e-nero") : nil
    }

    /// From the car's service list. A car that lists nothing gets every command, so an older or
    /// different account isn't locked out by a list it doesn't send.
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
        static let plate = "plate"
        static let carName = "carName"
        static let carColor = "carColor"
        static let ownerName = "ownerName"
        static let useMiles = "useMiles"
        static let onboarded = "onboarded"
        static let schedules = "schedules"
        static let lastPreheat = "lastPreheatStart"
    }

    private init() {
        selectedVIN = defaults.string(forKey: Keys.vin)
        plate = defaults.string(forKey: Keys.plate) ?? ""
        carName = defaults.string(forKey: Keys.carName) ?? "My car"
        carColorHex = defaults.string(forKey: Keys.carColor) ?? "#18181b"
        ownerName = defaults.string(forKey: Keys.ownerName)
        useMiles = defaults.bool(forKey: Keys.useMiles)
        onboarded = defaults.bool(forKey: Keys.onboarded)
        schedules = defaults.data(forKey: Keys.schedules)
            .flatMap { try? JSONDecoder().decode([PreheatSchedule].self, from: $0) } ?? []
        lastPreheatStart = defaults.object(forKey: Keys.lastPreheat) as? Date

        hasAccount = AccountStore.load() != nil

        if Demo.isActive {
            hasAccount = true
            onboarded = Demo.screen != "onboarding"
            vehicles = [Demo.vehicle]
            selectedVIN = Demo.vehicle.vin
            plate = "ED 35079"
            carName = "500e"
            ownerName = "Mikkel"
            carColorHex = "#18181b"
            status = Demo.status
            schedules = Demo.schedules
            location = Demo.location
            lastPreheatStart = Demo.screen == "preheating" ? Date().addingTimeInterval(-6 * 60) : nil
        }
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
        AccountStore.delete()
        await client.setAccount(nil)
        hasAccount = false
        onboarded = false
        vehicles = []
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
        do {
            // Fetched every time: the service list changes when a brand subscription starts or ends.
            vehicles = try await client.vehicles()
            if selectedVIN == nil || vehicle == nil { selectedVIN = vehicles.first?.vin }
            guard let vin = selectedVIN else { return }
            status = try await client.status(vin: vin)
            statusError = nil
        } catch {
            statusError = error.localizedDescription
        }
        publishSnapshot()
    }

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
            schedules = [schedule]
        }
        publishSnapshot()
    }

    func deleteSchedule() {
        schedules = []
    }

    /// Fired by a notification or background refresh: honours "only when plugged in".
    func scheduledPreheat() async {
        if schedule?.onlyWhenPluggedIn == true {
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
        commandState = .sending(command)
        if Demo.isActive {
            try? await Task.sleep(for: .seconds(1))
            recordAccepted(command)
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
            let result = await client.waitForResult(vin: vin, correlationId: correlationId)
            if result == .failed, command == .preconditionOn { setLastPreheat(nil) }
            if result == .failed, command == .lights { lastLightsOn = nil }
            if result == .succeeded { await followUp(command) }
            commandState = .done(command, result, Date())
        } catch {
            commandState = .failed(error.localizedDescription)
        }
        return commandState
    }

    private func recordAccepted(_ command: RemoteCommand) {
        switch command {
        case .preconditionOn: setLastPreheat(Date())
        case .preconditionOff: setLastPreheat(nil)
        case .lights: lastLightsOn = Date()
        default: break
        }
    }

    /// Reads back what a confirmed command changed, so the screen shows the car's new state.
    private func followUp(_ command: RemoteCommand) async {
        switch command {
        case .lock: status?.isLocked = true; publishSnapshot()
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
        let next = schedule.flatMap { s -> String? in
            guard s.isEnabled, let start = s.upcomingStarts(after: Date()).first else { return nil }
            return start.addingTimeInterval(TimeInterval(s.leadMinutes * 60)).formatted(.dateTime.weekday(.abbreviated).hour().minute())
        }
        CarSnapshot(carName: carName, plate: plate, stateOfCharge: status?.stateOfCharge, rangeKm: rangeKm, useMiles: useMiles,
                    isCharging: status?.isCharging == true, isPluggedIn: status?.isPluggedIn == true, isLocked: status?.isLocked,
                    preheatStartedAt: isPreheating ? lastPreheatStart : nil, nextSchedule: next, hasCarImage: carImage != nil,
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
