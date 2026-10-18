import SwiftUI

/// The car's recent drives from Fiat's eco-coaching: a summary of the last seven days, then each
/// trip with its distance, time, energy use and score, whichever of those the car reports.
struct TripsSheet: View {
    @Environment(CarModel.self) private var model
    @Environment(\.dismiss) private var dismiss
    @State private var trips: [Trip]?
    @State private var error: String?

    var body: some View {
        VStack(spacing: 0) {
            VSheetHeader(eyebrow: "Trips", title: model.carName) { dismiss() }
            ScrollView(showsIndicators: false) {
                VStack(spacing: 12) {
                    if let trips, !trips.isEmpty {
                        summary(trips)
                        VStack(spacing: 0) {
                            ForEach(trips) { trip in
                                if trip.id != trips.first?.id { Divider().overlay(V.outline).padding(.leading, 18) }
                                row(trip)
                            }
                        }
                        .background(RoundedRectangle(cornerRadius: V.radiusCard, style: .continuous).fill(V.raised))
                    } else if let error {
                        message(error)
                    } else if trips != nil {
                        message("No trips yet. They show up after the car has been driven.")
                    } else {
                        ProgressView().tint(V.text).padding(.top, 60)
                    }
                }
                .padding(.horizontal, V.gutter)
                .padding(.top, 20)
                .padding(.bottom, 32)
            }
        }
        .background(V.surface.ignoresSafeArea())
        .varmeSheet()
        .task {
            do { trips = try await model.loadTrips() } catch { self.error = Self.explain(error) }
        }
    }

    private func summary(_ trips: [Trip]) -> some View {
        let week = trips.filter { ($0.start ?? .distantPast) > Date().addingTimeInterval(-7 * 86_400) }
        let distance = week.compactMap(\.distanceKm).reduce(0, +)
        let consumptions = week.compactMap { t in t.consumption.map { ($0, t.distanceKm ?? 1) } }
        let weighted = consumptions.isEmpty ? nil : consumptions.map { $0.0 * $0.1 }.reduce(0, +) / consumptions.map(\.1).reduce(0, +)
        return HStack(spacing: 10) {
            stat("Last 7 days", value: distanceText(distance), unit: nil)
            if let weighted { stat("Average", value: String(format: "%.1f", weighted), unit: "kWh/100 km") }
        }
    }

    private func stat(_ label: String, value: String, unit: String?) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(label).font(V.label).foregroundStyle(V.textMuted)
            HStack(alignment: .firstTextBaseline, spacing: 4) {
                Text(value).font(V.sora(30, .light)).tracking(-1).foregroundStyle(V.text)
                if let unit { Text(unit).font(V.label).foregroundStyle(V.textMuted) }
            }
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(RoundedRectangle(cornerRadius: V.radiusCard, style: .continuous).fill(V.raised))
    }

    private func row(_ trip: Trip) -> some View {
        HStack(alignment: .center, spacing: 12) {
            VStack(alignment: .leading, spacing: 3) {
                Text(trip.start.map { $0.formatted(.dateTime.weekday(.abbreviated).day().month(.abbreviated).hour().minute()) } ?? "Trip")
                    .font(V.label).foregroundStyle(V.textMuted)
                HStack(spacing: 6) {
                    if let d = trip.distanceKm { Text(distanceText(d)).font(V.body).foregroundStyle(V.text) }
                    if let m = trip.minutes { Text("· \(Int(m.rounded())) min").font(V.body).foregroundStyle(V.textMuted) }
                }
            }
            Spacer(minLength: 8)
            VStack(alignment: .trailing, spacing: 3) {
                if let c = trip.consumption {
                    Text(String(format: "%.1f kWh", c)).font(V.body).foregroundStyle(V.text)
                    Text("per 100 km").font(V.label).foregroundStyle(V.textMuted)
                }
            }
            if let score = trip.score {
                Text("\(Int(score))").font(V.sora(13, .semibold)).foregroundStyle(V.ground)
                    .frame(width: 34, height: 34)
                    .background(Circle().fill(score >= 70 ? V.positive : score >= 40 ? V.amber : V.danger))
                    .accessibilityLabel("Eco score \(Int(score))")
            }
        }
        .padding(.horizontal, 18).padding(.vertical, 12)
    }

    private func message(_ text: String) -> some View {
        Text(text).font(V.body).foregroundStyle(V.textMuted).multilineTextAlignment(.center)
            .frame(maxWidth: .infinity).padding(.top, 60).padding(.horizontal, 20)
    }

    private func distanceText(_ km: Double) -> String {
        let value = model.useMiles ? km / 1.609 : km
        return String(format: value < 10 ? "%.1f %@" : "%.0f %@", value, model.useMiles ? "mi" : "km")
    }

    private static func explain(_ error: Error) -> String {
        if case UconnectError.requestFailed(let code, _) = error, code == 404 || code == 403 {
            return "Fiat doesn't share trips for this car or account."
        }
        return error.localizedDescription
    }
}
