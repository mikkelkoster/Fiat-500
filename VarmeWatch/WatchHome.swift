import SwiftUI

/// One scrolling screen: the battery, the preheat button, then lock, unlock and lights.
struct WatchHome: View {
    @EnvironmentObject private var model: WatchModel
    @State private var confirmUnlock = false

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 10) {
                    if let car = model.car {
                        header(car)
                        preheat(car)
                        HStack(spacing: 8) {
                            tile(icon: car.isLocked == false ? "lock" : "lock-open",
                                 title: car.isLocked == false ? "Lock" : "Unlock",
                                 command: car.isLocked == false ? "lock" : "unlock")
                            tile(icon: "lightbulb", title: "Lights", command: "lights")
                        }
                    } else {
                        VStack(spacing: 8) {
                            PhIcon(name: "car", size: 28).foregroundStyle(V.textMuted)
                            Text("Open Varme on your iPhone to connect your car.")
                                .font(V.sora(14)).foregroundStyle(V.textMuted).multilineTextAlignment(.center)
                        }
                        .padding(.top, 20)
                    }
                }
                .padding(.horizontal, 4)
            }
            .navigationTitle {
                Text(model.car?.carName ?? "Varme").font(V.sora(15, .semibold)).foregroundStyle(V.text)
            }
            .containerBackground(V.ground.gradient, for: .navigation)
            .overlay(alignment: .bottom) {
                if let message = model.message {
                    Text(message).font(V.sora(12)).foregroundStyle(V.text)
                        .padding(.horizontal, 12).padding(.vertical, 8)
                        .background(Capsule().fill(model.messageIsError ? V.danger.opacity(0.3) : V.raised))
                        .transition(.move(edge: .bottom).combined(with: .opacity))
                }
            }
            .animation(.easeOut(duration: 0.25), value: model.message)
        }
        .confirmationDialog("Unlock \(model.car?.carName ?? "the car")?", isPresented: $confirmUnlock) {
            Button("Unlock") { model.send("unlock") }
        }
    }

    private func header(_ car: CarSnapshot) -> some View {
        HStack(spacing: 10) {
            ZStack {
                Circle().stroke(V.raised, lineWidth: 5)
                Circle().trim(from: 0, to: CGFloat(min(100, max(0, car.stateOfCharge ?? 0))) / 100)
                    .stroke(car.isCharging ? V.positive : V.batteryColor(car.stateOfCharge), style: StrokeStyle(lineWidth: 5, lineCap: .round))
                    .rotationEffect(.degrees(-90))
                if car.isCharging { PhIcon(name: "lightning", size: 14).foregroundStyle(V.positive) }
            }
            .frame(width: 44, height: 44)
            VStack(alignment: .leading, spacing: 0) {
                HStack(alignment: .firstTextBaseline, spacing: 1) {
                    Text(car.stateOfCharge.map { "\(Int($0))" } ?? "–").font(V.sora(30, .ultraLight)).tracking(-1).foregroundStyle(V.text)
                    Text("%").font(V.sora(12)).foregroundStyle(V.textMuted)
                }
                HStack(spacing: 4) {
                    if let locked = car.isLocked {
                        Circle().fill(locked ? V.positive : V.danger).frame(width: 6, height: 6)
                    }
                    Text(car.rangeText).font(V.sora(12)).foregroundStyle(V.textMuted)
                }
            }
            Spacer(minLength: 0)
        }
        .padding(.bottom, 2)
    }

    @ViewBuilder private func preheat(_ car: CarSnapshot) -> some View {
        if car.isPreheating, let started = car.preheatStartedAt {
            Button { model.send("stop") } label: {
                VStack(spacing: 2) {
                    Text(timerInterval: Date()...started.addingTimeInterval(30 * 60), countsDown: true)
                        .font(V.sora(24, .ultraLight)).foregroundStyle(V.heat).monospacedDigit()
                    Text(model.sending == "stop" ? "Stopping…" : "Tap to stop").font(V.sora(11)).foregroundStyle(V.textMuted)
                }
                .frame(maxWidth: .infinity).padding(.vertical, 10)
                .background(RoundedRectangle(cornerRadius: 24, style: .continuous).fill(V.heat.opacity(0.12)))
                .overlay(RoundedRectangle(cornerRadius: 24, style: .continuous).strokeBorder(V.heat, lineWidth: 1.5))
            }
            .buttonStyle(.plain)
            .disabled(model.sending != nil)
        } else {
            Button { model.send("preheat") } label: {
                HStack(spacing: 8) {
                    if model.sending == "preheat" { ProgressView().tint(V.ground).frame(width: 18, height: 18) }
                    else { PhIcon(name: "flame", size: 18) }
                    Text(model.sending == "preheat" ? "Sending…" : "Heat").font(V.sora(16, .semibold))
                }
                .foregroundStyle(V.ground)
                .frame(maxWidth: .infinity).frame(height: 52)
                .background(Capsule().fill(V.text))
            }
            .buttonStyle(.plain)
            .disabled(model.sending != nil)
        }
    }

    private func tile(icon: String, title: String, command: String) -> some View {
        Button {
            if command == "unlock" { confirmUnlock = true } else { model.send(command) }
        } label: {
            VStack(spacing: 6) {
                if model.sending == command { ProgressView().frame(width: 20, height: 20) } else { PhIcon(name: icon, size: 20) }
                Text(title).font(V.sora(12))
            }
            .foregroundStyle(V.text)
            .frame(maxWidth: .infinity).frame(height: 64)
            .background(RoundedRectangle(cornerRadius: 20, style: .continuous).fill(V.surface))
            .overlay(RoundedRectangle(cornerRadius: 20, style: .continuous).strokeBorder(V.raised, lineWidth: 1))
        }
        .buttonStyle(.plain)
        .disabled(model.sending != nil)
    }
}
