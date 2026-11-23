// swift-tools-version: 6.0
import PackageDescription

// The mutation collector's fixture (M6): two libraries and two test
// targets, Swift Testing only, with no loops and nothing timed, so
// SwiftMutator's verdicts are the same on every recording. `CoreTests`
// holds most of the test code and depends on `Core`; `ExtrasTests` holds
// one small test and depends on `Extras`, so `Extras`' test-to-code line
// ratio is below the project's and `Core`'s isn't. Each function is one
// signal case (its comment says which). `Patches/` holds the edits the
// `--since` and stopped cases make.
// `Scripts/record-mutation-fixture.sh` runs SwiftMutator on a copy and
// records what it writes into `Recorded/mutation/`.
let package = Package(
    name: "MutationProbe",
    platforms: [.macOS(.v14)],
    targets: [
        .target(name: "Core"),
        .target(name: "Extras"),
        .testTarget(name: "CoreTests", dependencies: ["Core"]),
        .testTarget(name: "ExtrasTests", dependencies: ["Extras"])
    ]
)
