// swift-tools-version: 6.0
// A fixture for SwiftStats' law checks (M4): each provenance, state and
// implementation rule, and the conformances that make no pair, each checked
// by hand in LawCheckTests. It is parsed, never built: SwiftPropertyLaws
// and its macro are not dependencies.
import PackageDescription

let package = Package(
    name: "Laws",
    targets: [
        .target(name: "Core"),
        .target(name: "Extras", dependencies: ["Core"]),
        .testTarget(name: "CoreTests", dependencies: ["Core", "Extras"])
    ]
)
