import ActivityKit
import SwiftUI
import WidgetKit

@main
struct VarmeWidgetBundle: WidgetBundle {
    var body: some Widget {
        BatteryWidget()
        PreheatWidget()
        CarWidget()
        PreheatLiveActivity()
        if #available(iOS 18.0, *) {
            PreheatControl()
            LockControl()
        }
    }
}

// MARK: - Timeline

struct CarEntry: TimelineEntry {
    let date: Date
    let car: CarSnapshot
}

struct CarProvider: TimelineProvider {
    func placeholder(in context: Context) -> CarEntry { CarEntry(date: Date(), car: .placeholder) }
    func getSnapshot(in context: Context, completion: @escaping (CarEntry) -> Void) {
        completion(CarEntry(date: Date(), car: CarSnapshot.load() ?? .placeholder))
    }
    func getTimeline(in context: Context, completion: @escaping (Timeline<CarEntry>) -> Void) {
        let car = CarSnapshot.load() ?? .placeholder
        // One entry now; the app reloads timelines whenever the car's state changes.
        completion(Timeline(entries: [CarEntry(date: Date(), car: car)], policy: .after(Date().addingTimeInterval(30 * 60))))
    }
}

// MARK: - Shared pieces

private struct WidgetIcon: View {
    let name: String
    var size: CGFloat = 20
    var body: some View {
        Image("ph-\(name)").renderingMode(.template).resizable().aspectRatio(contentMode: .fit).frame(width: size, height: size)
    }
}

private func batteryColor(_ soc: Double?) -> Color {
    guard let soc else { return V.textMuted }
    return soc >= 40 ? V.positive : soc >= 15 ? V.amber : V.danger
}

private struct BatteryRing: View {
    let soc: Double?
    let charging: Bool
    var lineWidth: CGFloat = 7
    var body: some View {
        ZStack {
            Circle().stroke(V.raised, lineWidth: lineWidth)
            Circle().trim(from: 0, to: CGFloat(min(100, max(0, soc ?? 0))) / 100)
                .stroke(charging ? V.positive : batteryColor(soc), style: StrokeStyle(lineWidth: lineWidth, lineCap: .round))
                .rotationEffect(.degrees(-90))
        }
    }
}

private extension View {
    func varmeWidgetBackground() -> some View {
        containerBackground(for: .widget) { V.surface }
    }
}

// MARK: - Battery widget (small + lock screen)

struct BatteryWidget: Widget {
    var body: some WidgetConfiguration {
        StaticConfiguration(kind: "dk.koster.varme.battery", provider: CarProvider()) { entry in
            BatteryWidgetView(car: entry.car)
        }
        .configurationDisplayName("Battery")
        .description("Charge, range and whether the car is locked.")
        .supportedFamilies([.systemSmall, .accessoryCircular, .accessoryRectangular, .accessoryInline])
    }
}

struct BatteryWidgetView: View {
    @Environment(\.widgetFamily) private var family
    let car: CarSnapshot

    var body: some View {
        switch family {
        case .accessoryCircular:
            ZStack {
                AccessoryWidgetBackground()
                BatteryRing(soc: car.stateOfCharge, charging: car.isCharging, lineWidth: 5).padding(3)
                Text(car.stateOfCharge.map { "\(Int($0))" } ?? "–").font(.system(size: 15, weight: .semibold))
            }
            .widgetURL(VarmeLink.open)
        case .accessoryRectangular:
            VStack(alignment: .leading, spacing: 2) {
                Text("\(car.carName) · \(car.stateOfCharge.map { "\(Int($0)) %" } ?? "–")").font(.headline)
                Text("\(car.rangeText) · \(car.isLocked == true ? "locked" : car.isLocked == false ? "unlocked" : "")").font(.caption)
            }
            .widgetURL(VarmeLink.open)
        case .accessoryInline:
            Text("\(car.carName) \(car.stateOfCharge.map { "\(Int($0)) %" } ?? "") · \(car.rangeText)")
                .widgetURL(VarmeLink.open)
        default:
            VStack(alignment: .leading, spacing: 0) {
                HStack(alignment: .top) {
                    BatteryRing(soc: car.stateOfCharge, charging: car.isCharging).frame(width: 52, height: 52)
                    Spacer()
                    if let locked = car.isLocked {
                        HStack(spacing: 4) {
                            WidgetIcon(name: locked ? "lock" : "lock-open", size: 11)
                            Text(locked ? "Locked" : "Unlocked").font(V.sora(11))
                        }
                        .foregroundStyle(locked ? V.positive : V.danger)
                    }
                }
                Spacer()
                HStack(alignment: .firstTextBaseline, spacing: 2) {
                    Text(car.stateOfCharge.map { "\(Int($0))" } ?? "–").font(V.sora(34, .ultraLight)).tracking(-1.5).foregroundStyle(V.text)
                    Text("%").font(V.sora(14)).foregroundStyle(V.textMuted)
                }
                Text("\(car.rangeText) · \(car.carName)").font(V.sora(12)).foregroundStyle(V.textMuted).lineLimit(1)
            }
            .varmeWidgetBackground()
            .widgetURL(VarmeLink.open)
        }
    }
}

// MARK: - Preheat widget (small)

struct PreheatWidget: Widget {
    var body: some WidgetConfiguration {
        StaticConfiguration(kind: "dk.koster.varme.preheat", provider: CarProvider()) { entry in
            PreheatWidgetView(car: entry.car)
        }
        .configurationDisplayName("Heat")
        .description("One tap to warm the cabin.")
        .supportedFamilies([.systemSmall])
    }
}

struct PreheatWidgetView: View {
    let car: CarSnapshot
    var body: some View {
        let heating = car.isPreheating
        VStack(alignment: .leading, spacing: 0) {
            Circle().fill(heating ? V.heat : V.text).frame(width: 52, height: 52)
                .overlay(WidgetIcon(name: "flame", size: 26).foregroundStyle(V.ground))
            Spacer()
            Text(heating ? "Heating" : "Heat").font(V.sora(16, .semibold)).foregroundStyle(V.text)
            Text(heating ? car.carName : (car.nextSchedule.map { "Next: \($0)" } ?? car.carName)).font(V.sora(12)).foregroundStyle(V.textMuted).lineLimit(1)
        }
        .varmeWidgetBackground()
        .widgetURL(heating ? VarmeLink.open : VarmeLink.preheat)
    }
}

// MARK: - Car widget (medium)

struct CarWidget: Widget {
    var body: some WidgetConfiguration {
        StaticConfiguration(kind: "dk.koster.varme.car", provider: CarProvider()) { entry in
            CarWidgetView(car: entry.car)
        }
        .configurationDisplayName("Your car")
        .description("The car, its charge, and Preheat, Unlock and Find.")
        .supportedFamilies([.systemMedium])
    }
}

struct CarWidgetView: View {
    let car: CarSnapshot
    var body: some View {
        HStack(spacing: 6) {
            if car.hasCarImage {
                car.carPicture.resizable().aspectRatio(contentMode: .fit).frame(width: 150)
            }
            VStack(alignment: .leading, spacing: 8) {
                HStack(alignment: .firstTextBaseline, spacing: 2) {
                    Text(car.stateOfCharge.map { "\(Int($0))" } ?? "–").font(V.sora(32, .ultraLight)).tracking(-1.5).foregroundStyle(V.text)
                    Text("%").font(V.sora(13)).foregroundStyle(V.textMuted)
                }
                Text("\(car.rangeText) · \(car.isCharging ? "charging" : car.isPluggedIn ? "plugged in" : car.isLocked == true ? "locked" : "")")
                    .font(V.sora(12)).foregroundStyle(V.textMuted).lineLimit(1)
                GeometryReader { g in
                    ZStack(alignment: .leading) {
                        Capsule().fill(V.raised)
                        Capsule().fill(car.isCharging ? V.positive : batteryColor(car.stateOfCharge))
                            .frame(width: g.size.width * CGFloat(min(100, max(0, car.stateOfCharge ?? 0))) / 100)
                    }
                }
                .frame(height: 4)
                HStack(spacing: 8) {
                    Link(destination: car.isPreheating ? VarmeLink.open : VarmeLink.preheat) {
                        Circle().fill(car.isPreheating ? V.heat : V.text).frame(width: 40, height: 40)
                            .overlay(WidgetIcon(name: "flame", size: 18).foregroundStyle(V.ground))
                    }
                    Link(destination: car.isLocked == false ? VarmeLink.lock : VarmeLink.unlock) {
                        Circle().fill(V.raised).frame(width: 40, height: 40)
                            .overlay(Circle().strokeBorder(V.outline, lineWidth: 1))
                            .overlay(WidgetIcon(name: car.isLocked == false ? "lock-open" : "lock", size: 18).foregroundStyle(V.text))
                    }
                    Link(destination: VarmeLink.find) {
                        Circle().fill(V.raised).frame(width: 40, height: 40)
                            .overlay(Circle().strokeBorder(V.outline, lineWidth: 1))
                            .overlay(WidgetIcon(name: "map-pin", size: 18).foregroundStyle(V.text))
                    }
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .varmeWidgetBackground()
    }
}

// MARK: - Live Activity

struct PreheatLiveActivity: Widget {
    var body: some WidgetConfiguration {
        ActivityConfiguration(for: PreheatActivityAttributes.self) { context in
            LockScreenActivity(context: context)
                .activityBackgroundTint(V.surface)
                .activitySystemActionForegroundColor(V.text)
        } dynamicIsland: { context in
            DynamicIsland {
                DynamicIslandExpandedRegion(.leading) {
                    if CarSnapshot.load()?.hasCarImage ?? true {
                        (CarSnapshot.load() ?? .placeholder).carPicture.resizable().aspectRatio(contentMode: .fit).frame(width: 92)
                    } else {
                        WidgetIcon(name: "flame", size: 28).foregroundStyle(V.heat).padding(.top, 8)
                    }
                }
                DynamicIslandExpandedRegion(.center) {
                    VStack(alignment: .leading, spacing: 0) {
                        Text("Heating").font(V.sora(13)).foregroundStyle(V.textMuted)
                        Text(timerInterval: Date()...context.state.endDate, countsDown: true)
                            .font(V.sora(34, .ultraLight)).tracking(-1).foregroundStyle(V.heat).monospacedDigit()
                    }
                }
                DynamicIslandExpandedRegion(.trailing) {
                    Link(destination: VarmeLink.stop) {
                        Text("Stop").font(V.sora(14, .semibold)).foregroundStyle(V.ground)
                            .padding(.horizontal, 16).frame(height: 40).background(Capsule().fill(V.text))
                    }
                    .padding(.top, 10)
                }
                DynamicIslandExpandedRegion(.bottom) {
                    ProgressView(timerInterval: Date()...context.state.endDate, countsDown: false, label: { EmptyView() }, currentValueLabel: { EmptyView() })
                        .tint(V.heat)
                        .padding(.top, 4)
                }
            } compactLeading: {
                WidgetIcon(name: "flame", size: 18).foregroundStyle(V.heat)
            } compactTrailing: {
                Text(timerInterval: Date()...context.state.endDate, countsDown: true, showsHours: false)
                    .font(V.sora(14, .semibold)).foregroundStyle(V.heat).monospacedDigit().frame(width: 44)
            } minimal: {
                ProgressView(timerInterval: Date()...context.state.endDate, countsDown: false, label: { EmptyView() }, currentValueLabel: { EmptyView() })
                    .progressViewStyle(.circular).tint(V.heat)
            }
            .keylineTint(V.heat)
        }
    }
}

private struct LockScreenActivity: View {
    let context: ActivityViewContext<PreheatActivityAttributes>
    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                HStack(spacing: 10) {
                    Circle().fill(V.heat.opacity(0.18)).frame(width: 32, height: 32)
                        .overlay(WidgetIcon(name: "flame", size: 18).foregroundStyle(V.heat))
                    Text("Heating \(context.attributes.carName)").font(V.sora(14, .semibold)).foregroundStyle(V.text)
                }
                Spacer()
                Text(context.attributes.plate).font(V.sora(12)).foregroundStyle(V.textMuted)
            }
            HStack(alignment: .bottom) {
                VStack(alignment: .leading, spacing: 2) {
                    Text(timerInterval: Date()...context.state.endDate, countsDown: true)
                        .font(V.sora(44, .ultraLight)).tracking(-2).foregroundStyle(V.heat).monospacedDigit()
                    Text([context.state.warmBy.map { "Warm by \($0)" }, context.state.stateOfCharge.map { "\($0) %" }, context.state.rangeText]
                        .compactMap { $0 }.joined(separator: " · "))
                        .font(V.sora(13)).foregroundStyle(V.textMuted)
                }
                Spacer()
                Link(destination: VarmeLink.stop) {
                    Text("Stop").font(V.sora(14, .semibold)).foregroundStyle(V.ground)
                        .padding(.horizontal, 18).frame(height: 40).background(Capsule().fill(V.text))
                }
            }
            ProgressView(timerInterval: Date()...context.state.endDate, countsDown: false, label: { EmptyView() }, currentValueLabel: { EmptyView() })
                .tint(V.heat)
        }
        .padding(16)
    }
}

// MARK: - Control Center (iOS 18)

@available(iOS 18.0, *)
struct PreheatControl: ControlWidget {
    var body: some ControlWidgetConfiguration {
        StaticControlConfiguration(kind: "dk.koster.varme.control.preheat") {
            ControlWidgetButton(action: OpenVarmeIntent(link: "preheat")) {
                Label("Heat cabin", systemImage: "flame")
            }
        }
        .displayName("Heat cabin")
        .description("Warm the cabin.")
    }
}

@available(iOS 18.0, *)
struct LockControl: ControlWidget {
    var body: some ControlWidgetConfiguration {
        StaticControlConfiguration(kind: "dk.koster.varme.control.lock") {
            ControlWidgetButton(action: OpenVarmeIntent(link: "lock")) {
                Label("Lock car", systemImage: "lock")
            }
        }
        .displayName("Lock car")
        .description("Lock the doors.")
    }
}
