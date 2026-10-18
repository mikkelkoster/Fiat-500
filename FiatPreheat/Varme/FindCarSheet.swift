import CoreLocation
import MapKit
import SwiftUI

/// Where the car last reported itself: a map that fills the sheet, Update to ask the car again,
/// Directions (Apple Maps, walking) and Flash lights at the bottom.
struct FindCarSheet: View {
    @Environment(CarModel.self) private var model
    @Environment(\.dismiss) private var dismiss
    @Environment(\.openURL) private var openURL
    @State private var camera: MapCameraPosition = .automatic
    @State private var address: String?
    @State private var distance: CLLocationDistance?
    @StateObject private var locator = Locator()

    var body: some View {
        VStack(spacing: 0) {
            VSheetHeader(eyebrow: "Find car", title: address ?? model.carName, subtitle: subtitle) { dismiss() }

            ZStack(alignment: .topTrailing) {
                if let location = model.location {
                    Map(position: $camera) {
                        if let me = locator.location {
                            UserAnnotation()
                            MapPolyline(coordinates: [me.coordinate, location.coordinate]).stroke(V.cool, style: StrokeStyle(lineWidth: 3, dash: [1, 9], dashPhase: 0))
                        }
                        Annotation(model.plate, coordinate: location.coordinate) {
                            Circle().fill(V.text).frame(width: 44, height: 44)
                                .overlay(PhIcon(name: "car", size: 22).foregroundStyle(V.ground))
                        }
                    }
                    .mapStyle(.standard(elevation: .flat, pointsOfInterest: .excludingAll))
                    .mapControls { }
                    .colorScheme(.dark)
                } else {
                    V.raised
                    Text(model.locationError ?? "Loading the last known position…")
                        .font(V.body).foregroundStyle(V.textMuted).multilineTextAlignment(.center)
                        .frame(maxWidth: .infinity, maxHeight: .infinity).padding(V.gutter)
                }
                Button { Task { await model.perform(.locate) } } label: {
                    HStack(spacing: 6) {
                        PhIcon(name: "arrows-clockwise", size: 14)
                        Text(updating ? "Asking the car…" : "Update").font(V.label)
                    }
                    .foregroundStyle(V.text)
                    .padding(.horizontal, 12).frame(height: 36)
                    .background(Capsule().fill(V.surface.opacity(0.92)))
                    .overlay(Capsule().strokeBorder(V.raised, lineWidth: 1))
                }
                .buttonStyle(PressStyle())
                .disabled(model.isBusy || model.availability(of: .locate) != .available)
                .padding(12)
            }
            .clipShape(RoundedRectangle(cornerRadius: V.radiusCard, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: V.radiusCard, style: .continuous).strokeBorder(V.raised, lineWidth: 1))
            .padding(.horizontal, V.gutter)
            .padding(.top, 16)

            HStack(spacing: 10) {
                VButton(title: "Directions", icon: "navigation-arrow") {
                    if let location = model.location { openURL(location.directionsURL) }
                }
                .disabled(model.location == nil)
                VButton(title: model.isLightsOn ? "Lights on" : "Flash lights", icon: "lightbulb", prominent: false) {
                    Task { await model.perform(.lights) }
                }
                .disabled(model.isBusy || model.availability(of: .lights) != .available)
            }
            .padding(.horizontal, V.gutter)
            .padding(.vertical, 14)
            .padding(.bottom, 10)
        }
        .background(V.surface.ignoresSafeArea())
        .varmeSheet()
        .task {
            locator.start()
            if let location = model.location { camera = .region(location.region) }
            await model.loadLocation()
            await describe()
        }
        .onChange(of: model.location) { _, location in
            guard let location else { return }
            withAnimation { camera = .region(location.region) }
            Task { await describe() }
        }
        .onChange(of: locator.location) { _, _ in updateDistance() }
    }

    private var updating: Bool {
        switch model.commandState {
        case .sending(.locate), .waitingForCar(.locate): true
        default: false
        }
    }

    private var subtitle: String? {
        guard let location = model.location else { return nil }
        var parts: [String] = []
        if let distance {
            parts.append(distance < 1000 ? "\(Int(distance)) m" : String(format: "%.1f km", distance / 1000))
            parts.append("\(max(1, Int(distance / 80))) min walk")
        }
        if let when = location.updatedAt { parts.append("seen \(when.formatted(.relative(presentation: .named)))") }
        return parts.isEmpty ? nil : parts.joined(separator: " · ")
    }

    private func describe() async {
        guard let location = model.location else { return }
        updateDistance()
        let place = try? await CLGeocoder().reverseGeocodeLocation(CLLocation(latitude: location.latitude, longitude: location.longitude)).first
        if let place {
            address = [place.thoroughfare, place.subThoroughfare].compactMap { $0 }.joined(separator: " ").nilIfEmpty ?? place.locality
        }
    }

    private func updateDistance() {
        guard let car = model.location, let me = locator.location else { return }
        distance = me.distance(from: CLLocation(latitude: car.latitude, longitude: car.longitude))
    }
}

private extension String {
    var nilIfEmpty: String? { isEmpty ? nil : self }
}

extension CarLocation {
    var coordinate: CLLocationCoordinate2D { CLLocationCoordinate2D(latitude: latitude, longitude: longitude) }
    var region: MKCoordinateRegion { MKCoordinateRegion(center: coordinate, latitudinalMeters: 700, longitudinalMeters: 700) }
    /// Apple Maps, walking from wherever the phone is.
    var directionsURL: URL { URL(string: "https://maps.apple.com/?daddr=\(latitude),\(longitude)&dirflg=w")! }
}

/// The phone's position, for the distance line and the route on the map.
final class Locator: NSObject, ObservableObject, CLLocationManagerDelegate {
    @Published var location: CLLocation?
    private let manager = CLLocationManager()

    func start() {
        manager.delegate = self
        manager.desiredAccuracy = kCLLocationAccuracyHundredMeters
        if manager.authorizationStatus == .notDetermined { manager.requestWhenInUseAuthorization() } else { manager.requestLocation() }
    }

    func locationManagerDidChangeAuthorization(_ manager: CLLocationManager) {
        if manager.authorizationStatus == .authorizedWhenInUse || manager.authorizationStatus == .authorizedAlways { manager.requestLocation() }
    }

    func locationManager(_ manager: CLLocationManager, didUpdateLocations locations: [CLLocation]) { location = locations.last }
    func locationManager(_ manager: CLLocationManager, didFailWithError error: Error) {}
}
