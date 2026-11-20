// swift-tools-version: 6.0
// A fixture for SwiftStats' clone collector (M4): an exact whole-function
// copy across two modules, a renamed copy of a type, copied statements
// inside different functions, runs of copied statements, near-miss
// pairs, plus a generated file and a test file that are never passed to
// the tool. It is parsed, never built. Recorded/ holds the JSON that
// swift-clone-detector at 97eee1c wrote over the eight production files,
// byte-sorted, with SwiftStats' flags: default.json, type3.json,
// sequence.json and type1.json for the four runs, and all.json for its
// own merge (--all), which SwiftStats' merge must reproduce.
import PackageDescription

let package = Package(
    name: "Clones",
    targets: [
        .target(name: "Core"),
        .target(name: "Extras", dependencies: ["Core"]),
        .testTarget(name: "CoreTests", dependencies: ["Core"])
    ]
)
