import Foundation
import Observation

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

    private(set) var hasAccount = false
    private(set) var vehicles: [Vehicle] = []
    private(set) var status: VehicleStatus?
    private(set) var commandState: CommandState = .idle
    private(set) var lastPreheatStart: Date?
    private(set) var statusError: String?
    private(set) var location: CarLocation?
    private(set) var locationError: String?

    /// Whether the car offers a command and whether the account has it switched on.
    enum Availability { case available, needsSubscription, unsupported }

    var selectedVIN: String? {
        didSet { defaults.set(selectedVIN, forKey: Keys.vin) }
    }
    var plate: String {
        didSet { defaults.set(plate, forKey: Keys.plate) }
    }
    var schedules: [PreheatSchedule] {
        didSet {
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

    var vehicle: Vehicle? { vehicles.first { $0.vin == selectedVIN } }

    /// From the car's service list. A car that lists nothing gets every command, so an older or
    /// different account isn't locked out by a list it doesn't send.
    func availability(of command: RemoteCommand) -> Availability {
        guard let vehicle, !vehicle.services.isEmpty || !vehicle.disabledServices.isEmpty else { return .available }
        if vehicle.services.contains(command.rawValue) { return .available }
        if vehicle.disabledServices.contains(command.rawValue) { return .needsSubscription }
        return .unsupported
    }

    var isBusy: Bool {
        switch commandState {
        case .sending, .waitingForCar: true
        default: false
        }
    }

    private let client = UconnectClient()
    private let defaults = UserDefaults.standard

    private enum Keys {
        static let vin = "selectedVIN"
        static let plate = "plate"
        static let schedules = "schedules"
        static let lastPreheat = "lastPreheatStart"
    }

    private init() {
        selectedVIN = defaults.string(forKey: Keys.vin)
        plate = defaults.string(forKey: Keys.plate) ?? "ED35079"
        schedules = defaults.data(forKey: Keys.schedules)
            .flatMap { try? JSONDecoder().decode([PreheatSchedule].self, from: $0) } ?? []
        lastPreheatStart = defaults.object(forKey: Keys.lastPreheat) as? Date

        hasAccount = AccountStore.load() != nil

        if Demo.isActive {
            hasAccount = true
            vehicles = [Demo.vehicle]
            selectedVIN = Demo.vehicle.vin
            plate = "ED35079"
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
        await refreshStatus()
    }

    func signOut() async {
        AccountStore.delete()
        await client.setAccount(nil)
        hasAccount = false
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
            // Fetched every time: the service list changes when a Fiat subscription starts or ends.
            vehicles = try await client.vehicles()
            if selectedVIN == nil || vehicle == nil { selectedVIN = vehicles.first?.vin }
            guard let vin = selectedVIN else { return }
            status = try await client.status(vin: vin)
            statusError = nil
        } catch {
            statusError = error.localizedDescription
        }
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
        default: break
        }
    }

    /// Reads back what a confirmed command changed, so the screen shows the car's new state.
    private func followUp(_ command: RemoteCommand) async {
        switch command {
        case .lock: status?.isLocked = true
        case .unlock: status?.isLocked = false
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
    }
}
