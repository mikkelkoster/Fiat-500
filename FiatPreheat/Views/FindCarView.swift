import MapKit
import SwiftUI

/// Where the car last reported itself, with a button to ask it again and walking directions.
struct FindCarView: View {
    @Environment(CarModel.self) private var model
    @Environment(\.dismiss) private var dismiss
    @Environment(\.openURL) private var openURL
    @State private var camera: MapCameraPosition = .automatic

    var body: some View {
        VStack(spacing: 0) {
            SheetHeader(title: "Find car", subtitle: subtitle) { dismiss() }

            ZStack {
                if let location = model.location {
                    Map(position: $camera) {
                        Marker(model.plate, systemImage: "car.fill", coordinate: location.coordinate)
                            .tint(Ink.primary)
                    }
                    .mapControls { MapCompass() }
                } else {
                    Rectangle().fill(Ink.card)
                    Text(model.locationError ?? "Loading the last known position…")
                        .font(Type.body).foregroundStyle(Ink.secondary)
                        .multilineTextAlignment(.center)
                        .padding(Space.gutter)
                }
            }
            .clipShape(RoundedRectangle(cornerRadius: Radius.card, style: .continuous))
            .padding(.horizontal, Space.gutter)

            VStack(spacing: 10) {
                PrimaryButton(title: updateTitle, icon: "location.fill", outline: true) {
                    Task { await model.perform(.locate) }
                }
                .disabled(model.isBusy || model.availability(of: .locate) != .available)
                PrimaryButton(title: "Walking directions", icon: "figure.walk") {
                    if let location = model.location { openURL(location.directionsURL) }
                }
                .disabled(model.location == nil)
            }
            .padding(Space.gutter)
        }
        .background(Ink.background.ignoresSafeArea())
        .task {
            if let location = model.location { camera = .region(location.region) }
            await model.loadLocation()
        }
        .onChange(of: model.location) { _, location in
            guard let location else { return }
            withAnimation { camera = .region(location.region) }
        }
    }

    private var subtitle: String {
        guard let location = model.location else { return "" }
        let when = location.updatedAt.map { "Last seen \($0.formatted(date: .abbreviated, time: .shortened))" } ?? "Last known position"
        return location.isApproximate ? "\(when), approximate" : when
    }

    private var updateTitle: String {
        switch model.commandState {
        case .sending(.locate): "Asking the car…"
        case .waitingForCar(.locate): "Waiting for the car…"
        default: "Update location"
        }
    }
}

extension CarLocation {
    var coordinate: CLLocationCoordinate2D { CLLocationCoordinate2D(latitude: latitude, longitude: longitude) }

    var region: MKCoordinateRegion {
        MKCoordinateRegion(center: coordinate, latitudinalMeters: 600, longitudinalMeters: 600)
    }

    /// Apple Maps, walking from wherever the phone is.
    var directionsURL: URL {
        URL(string: "https://maps.apple.com/?daddr=\(latitude),\(longitude)&dirflg=w")!
    }
}
