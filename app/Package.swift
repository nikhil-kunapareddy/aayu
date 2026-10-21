// swift-tools-version:6.0
// Aayu's SwiftUI front end. Built by `make run` / `make app`, which wrap the
// `Aayu` binary in Aayu.app together with the Python backend (see
// scripts/bundle.sh).
//
// All the code is in the AayuKit library so tests can reach it; the Aayu
// executable only starts the app. Tests use Swift Testing (`swift test`).
import PackageDescription

let package = Package(
    name: "Aayu",
    platforms: [.macOS(.v15)],
    products: [
        .executable(name: "Aayu", targets: ["Aayu"]),
    ],
    targets: [
        .target(name: "AayuKit", path: "Sources/AayuKit"),
        .executableTarget(name: "Aayu", dependencies: ["AayuKit"], path: "Sources/Aayu"),
        .testTarget(name: "AayuKitTests", dependencies: ["AayuKit"], path: "Tests/AayuKitTests",
                    resources: [.copy("Fixtures")]),
    ],
    swiftLanguageModes: [.v6]
)
