// swift-tools-version: 6.0
// Fixture for SwiftStats' golden scan test (PRD M0 done-when 1). Not built:
// the test only scans it. Every function kind in PRD §6.1a appears at least
// once; AllKinds.golden.json holds the expected output.
import PackageDescription

let package = Package(
    name: "AllKinds",
    targets: [
        .target(name: "AllKinds"),
        .executableTarget(name: "Tool", dependencies: ["AllKinds"]),
        .testTarget(name: "AllKindsTests", dependencies: ["AllKinds"])
    ]
)
