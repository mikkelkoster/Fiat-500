import SwiftUI
import WidgetKit

@main
struct VarmeComplicationsBundle: WidgetBundle {
    var body: some Widget {
        BatteryComplication()
        PreheatComplication()
    }
}

struct ComplicationEntry: TimelineEntry {
    let date: Date
    let car: CarSnapshot
}

struct ComplicationProvider: TimelineProvider {
    func placeholder(in context: Context) -> ComplicationEntry { ComplicationEntry(date: Date(), car: .placeholder) }
    func getSnapshot(in context: Context, completion: @escaping (ComplicationEntry) -> Void) {
        completion(ComplicationEntry(date: Date(), car: CarSnapshot.load() ?? .placeholder))
    }
    func getTimeline(in context: Context, completion: @escaping (Timeline<ComplicationEntry>) -> Void) {
        let car = CarSnapshot.load() ?? .placeholder
        var entries = [ComplicationEntry(date: Date(), car: car)]
        // While heating, one more entry when it should have finished so the face falls back.
        if car.isPreheating, let started = car.preheatStartedAt {
            var after = car; after.preheatStartedAt = nil
            entries.append(ComplicationEntry(date: started.addingTimeInterval(30 * 60), car: after))
        }
        completion(Timeline(entries: entries, policy: .after(Date().addingTimeInterval(30 * 60))))
    }
}

private func ringColor(_ car: CarSnapshot) -> Color {
    car.isCharging ? V.positive : V.batteryColor(car.stateOfCharge)
}

/// Battery on the watch face: a ring with the %, a corner gauge, a line of text, or a rectangle.
struct BatteryComplication: Widget {
    var body: some WidgetConfiguration {
        StaticConfiguration(kind: "dk.koster.varme.watch.battery", provider: ComplicationProvider()) { entry in
            BatteryComplicationView(car: entry.car).containerBackground(.clear, for: .widget)
        }
        .configurationDisplayName("Battery")
        .description("Your car's charge and range.")
        .supportedFamilies([.accessoryCircular, .accessoryCorner, .accessoryInline, .accessoryRectangular])
    }
}

struct BatteryComplicationView: View {
    @Environment(\.widgetFamily) private var family
    let car: CarSnapshot
    private var soc: Double { min(100, max(0, car.stateOfCharge ?? 0)) }

    var body: some View {
        switch family {
        case .accessoryCircular:
            Gauge(value: soc, in: 0...100) {
                Image("ph-lightning").renderingMode(.template).resizable().frame(width: 10, height: 10)
            } currentValueLabel: {
                Text(car.stateOfCharge.map { "\(Int($0))" } ?? "–")
            }
            .gaugeStyle(.accessoryCircular)
            .tint(ringColor(car))
        case .accessoryCorner:
            Text(car.stateOfCharge.map { "\(Int($0))%" } ?? "–")
                .widgetCurvesContent()
                .widgetLabel {
                    Gauge(value: soc, in: 0...100) { EmptyView() }.tint(ringColor(car))
                }
        case .accessoryInline:
            Text("\(car.carName) \(car.stateOfCharge.map { "\(Int($0))%" } ?? "") · \(car.rangeText)")
        default:
            VStack(alignment: .leading, spacing: 2) {
                Text(car.carName).font(.headline).widgetAccentable()
                Text("\(car.stateOfCharge.map { "\(Int($0)) %" } ?? "–") · \(car.rangeText)")
                Text(car.isPreheating ? "Preheating" : car.isLocked == true ? "Locked" : car.isLocked == false ? "Unlocked" : (car.isCharging ? "Charging" : ""))
                    .foregroundStyle(car.isPreheating ? V.heat : .secondary)
            }
        }
    }
}

/// A one-tap way into the app to preheat; orange while heating.
struct PreheatComplication: Widget {
    var body: some WidgetConfiguration {
        StaticConfiguration(kind: "dk.koster.varme.watch.preheat", provider: ComplicationProvider()) { entry in
            ZStack {
                AccessoryWidgetBackground()
                Image("ph-flame").renderingMode(.template).resizable().aspectRatio(contentMode: .fit).padding(12)
                    .foregroundStyle(entry.car.isPreheating ? V.heat : .white)
                    .widgetAccentable()
            }
            .containerBackground(.clear, for: .widget)
        }
        .configurationDisplayName("Preheat")
        .description("Open Varme to warm the cabin.")
        .supportedFamilies([.accessoryCircular])
    }
}
