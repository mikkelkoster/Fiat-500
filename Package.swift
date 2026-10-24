// swift-tools-version:5.9
// A command-line tool that runs the app's own Uconnect code (FiatPreheat/Uconnect) on a Mac, to
// test signing in and talking to the car without Xcode signing or a phone. See README.
import PackageDescription

let package = Package(
    name: "FiatPreheatTools",
    platforms: [.macOS(.v14)],
    targets: [
        .executableTarget(
            name: "fiat-cli",
            path: ".",
            sources: ["FiatPreheat/Uconnect", "Tools/fiat-cli"]
        ),
    ]
)
