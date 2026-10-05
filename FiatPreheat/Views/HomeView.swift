import SwiftUI

struct HomeView: View {
    @Environment(CarModel.self) private var model
    @State private var showSettings = false
    @State private var editing: PreheatSchedule?

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 24) {
                    CarCard(plate: model.plate, status: model.status, error: model.statusError)
                    PreheatButton()
                    SchedulesSection(editing: $editing)
                }
                .padding(.horizontal, 16)
                .padding(.bottom, 32)
            }
            .background(Color(.systemGroupedBackground))
            .navigationTitle("Fiat 500e")
            .toolbar {
                Button("Settings", systemImage: "gearshape") { showSettings = true }
            }
            .refreshable { await model.refreshStatus() }
            .sheet(isPresented: $showSettings) { SettingsView() }
            .sheet(item: $editing) { schedule in
                ScheduleEditorView(schedule: schedule)
            }
            .task {
                if model.hasAccount {
                    await model.refreshStatus()
                } else {
                    showSettings = true
                }
            }
        }
        .tint(.preheat)
    }
}

// MARK: - Car

private struct CarCard: View {
    let plate: String
    let status: VehicleStatus?
    let error: String?

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack(alignment: .top) {
                VStack(alignment: .leading, spacing: 4) {
                    Text("500e")
                        .font(.system(.largeTitle, design: .rounded, weight: .bold))
                    if let updated = status?.updatedAt {
                        Text("Updated \(updated, format: .relative(presentation: .named))")
                            .font(.footnote)
                            .foregroundStyle(.secondary)
                    }
                }
                Spacer()
                LicensePlate(text: plate)
            }

            HStack(spacing: 24) {
                Metric(
                    value: status?.stateOfCharge.map { "\(Int($0))%" } ?? "–",
                    label: "Battery",
                    symbol: batterySymbol
                )
                Metric(
                    value: status?.range.map { "\(Int($0)) \(status?.rangeUnit ?? "km")" } ?? "–",
                    label: "Range",
                    symbol: "road.lanes"
                )
                if status?.isPluggedIn == true {
                    Metric(
                        value: status?.isCharging == true ? "Charging" : "Plugged in",
                        label: "Cable",
                        symbol: "powerplug.fill"
                    )
                }
            }

            if let error {
                Label(error, systemImage: "exclamationmark.triangle.fill")
                    .font(.footnote)
                    .foregroundStyle(.orange)
                    .lineLimit(2)
            }
        }
        .padding(20)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(.background, in: .rect(cornerRadius: 24))
    }

    private var batterySymbol: String {
        guard let soc = status?.stateOfCharge else { return "battery.0percent" }
        switch soc {
        case ..<13: return "battery.0percent"
        case ..<38: return "battery.25percent"
        case ..<63: return "battery.50percent"
        case ..<88: return "battery.75percent"
        default: return "battery.100percent"
        }
    }
}

private struct Metric: View {
    let value: String
    let label: String
    let symbol: String

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            Label(label, systemImage: symbol)
                .font(.caption)
                .foregroundStyle(.secondary)
            Text(value)
                .font(.system(.title3, design: .rounded, weight: .semibold))
                .monospacedDigit()
        }
    }
}

/// Danish number plate: white, red frame, EU band with "DK".
struct LicensePlate: View {
    let text: String

    private var formatted: String {
        let compact = text.replacingOccurrences(of: " ", with: "").uppercased()
        guard compact.count > 2 else { return compact }
        return "\(compact.prefix(2)) \(compact.dropFirst(2))"
    }

    var body: some View {
        HStack(spacing: 0) {
            VStack(spacing: 1) {
                Image(systemName: "star.circle")
                    .font(.system(size: 9))
                    .foregroundStyle(.yellow)
                Text("DK")
                    .font(.system(size: 9, weight: .bold))
                    .foregroundStyle(.white)
            }
            .frame(width: 18)
            .frame(maxHeight: .infinity)
            .background(Color(red: 0, green: 0.2, blue: 0.6))

            Text(formatted)
                .font(.system(size: 17, weight: .semibold, design: .monospaced))
                .foregroundStyle(.black)
                .padding(.horizontal, 8)
        }
        .frame(height: 30)
        .background(.white)
        .clipShape(.rect(cornerRadius: 4))
        .overlay(RoundedRectangle(cornerRadius: 4).strokeBorder(Color(red: 0.8, green: 0.1, blue: 0.15), lineWidth: 2))
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Plate \(text)")
    }
}

// MARK: - Preheat

private struct PreheatButton: View {
    @Environment(CarModel.self) private var model

    var body: some View {
        // Re-evaluate `isPreheating` once a minute so the button falls back after the run ends.
        TimelineView(.periodic(from: .now, by: 60)) { _ in
            let active = model.isPreheating
            VStack(spacing: 16) {
                Button {
                    Task {
                        if active { await model.stopPreheat() } else { await model.startPreheat() }
                    }
                } label: {
                    ZStack {
                        Circle()
                            .fill(active ? AnyShapeStyle(Color.preheat.gradient) : AnyShapeStyle(.background))
                            .shadow(color: active ? .preheat.opacity(0.45) : .black.opacity(0.08), radius: active ? 24 : 12, y: 6)
                        if model.isBusy {
                            ProgressView().controlSize(.large).tint(active ? .white : .preheat)
                        } else {
                            VStack(spacing: 8) {
                                Image(systemName: active ? "stop.fill" : "thermometer.sun.fill")
                                    .font(.system(size: 44, weight: .medium))
                                    .symbolEffect(.pulse, isActive: active)
                                Text(active ? "Stop" : "Preheat")
                                    .font(.system(.title3, design: .rounded, weight: .semibold))
                            }
                            .foregroundStyle(active ? .white : .preheat)
                        }
                    }
                    .frame(width: 190, height: 190)
                }
                .buttonStyle(.plain)
                .disabled(model.isBusy || !model.hasAccount)
                .sensoryFeedback(.impact, trigger: model.isBusy)
                .accessibilityLabel(active ? "Stop preheating" : "Start preheating")

                Text(statusText(active: active))
                    .font(.subheadline)
                    .foregroundStyle(isError ? .red : .secondary)
                    .multilineTextAlignment(.center)
                    .frame(minHeight: 40)
                    .animation(.default, value: model.commandState)
            }
            .padding(.vertical, 8)
        }
    }

    private var isError: Bool {
        switch model.commandState {
        case .failed, .done(_, .failed, _): true
        default: false
        }
    }

    private func statusText(active: Bool) -> String {
        switch model.commandState {
        case .sending: return "Sending to the car…"
        case .waitingForCar: return "Waiting for the car to confirm…"
        case .failed(let message): return message
        case .done(_, .failed, _): return "The car didn't accept the command. Is it parked with enough charge?"
        case .done(.preconditionOff, _, _): return "Climate off."
        case .done(.preconditionOn, .unknown, _): return "Sent. The car hasn't confirmed yet. It may be in a weak signal area."
        case .done(.preconditionOn, .succeeded, _), .idle:
            guard active, let start = model.lastPreheatStart else { return " " }
            return "Preheating since \(start.formatted(date: .omitted, time: .shortened))"
        }
    }
}

// MARK: - Schedules

private struct SchedulesSection: View {
    @Environment(CarModel.self) private var model
    @Binding var editing: PreheatSchedule?

    var body: some View {
        @Bindable var model = model
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text("Schedules").font(.title3.weight(.semibold))
                Spacer()
                Button("Add", systemImage: "plus") {
                    editing = PreheatSchedule()
                }
                .labelStyle(.iconOnly)
                .font(.title3)
            }

            if model.schedules.isEmpty {
                Text("Add a schedule to have the car warm when you leave, e.g. weekdays at 07:30.")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(16)
                    .background(.background, in: .rect(cornerRadius: 16))
            }

            ForEach($model.schedules) { $schedule in
                Button { editing = schedule } label: {
                    HStack {
                        VStack(alignment: .leading, spacing: 2) {
                            Text(schedule.readyTimeText)
                                .font(.system(size: 34, weight: .semibold, design: .rounded))
                                .monospacedDigit()
                            Text("\(schedule.daysText) · starts \(String(format: "%02d:%02d", schedule.start.hour, schedule.start.minute))")
                                .font(.footnote)
                                .foregroundStyle(.secondary)
                        }
                        Spacer()
                        Toggle("Enabled", isOn: $schedule.isEnabled).labelsHidden()
                    }
                    .opacity(schedule.isEnabled ? 1 : 0.5)
                    .padding(16)
                    .background(.background, in: .rect(cornerRadius: 16))
                }
                .buttonStyle(.plain)
            }
        }
    }
}

extension Color {
    static let preheat = Color(red: 0.93, green: 0.36, blue: 0.16)
}
