// swift-tools-version: 6.0
import PackageDescription

// The risky + untested fixture (M5): crash and race markers in code the
// tests run, in code they don't, and where coverage can't say. `Risky`
// holds the cases, one file of them generated, `Orphan` is a library no
// test links, and `RiskyTests` runs part of `Risky`, its tests in `Unit/`
// below a file holding none.
// `Scripts/record-coverage-fixture.sh <work directory> Risky` builds a copy
// and records what the tools print into `Recorded/`.
let package = Package(
    name: "RiskyProbe",
    platforms: [.macOS(.v14)],
    targets: [
        .target(name: "Risky"),
        .target(name: "Orphan"),
        .testTarget(name: "RiskyTests", dependencies: ["Risky"])
    ]
)
