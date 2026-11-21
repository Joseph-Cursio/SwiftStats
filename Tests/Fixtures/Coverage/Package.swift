// swift-tools-version: 6.0
import PackageDescription

// The coverage collector's fixture (M5): a library and two test targets,
// one of whose names shares the words `Swift` and `Test` with SwiftPM's
// generated runner, so the runner's mangled name substitutes them.
// `Scripts/record-coverage-fixture.sh` builds a copy and records what the
// tools print into `Recorded/`.
let package = Package(
    name: "CoverageProbe",
    platforms: [.macOS(.v14)],
    targets: [
        .target(name: "Probe"),
        .testTarget(name: "ProbeTests", dependencies: ["Probe"]),
        .testTarget(name: "SwiftTestKitTests", dependencies: ["Probe"])
    ]
)
