// swift-tools-version:6.0
// Aayu's SwiftUI front end. Built by `make run` / `make app`, which wrap the
// binary in Aayu.app together with the Python backend (see scripts/bundle.sh).
import PackageDescription

let package = Package(
    name: "Aayu",
    platforms: [.macOS(.v15)],
    targets: [
        .executableTarget(name: "Aayu", path: "Sources/Aayu"),
    ],
    swiftLanguageModes: [.v5]
)
