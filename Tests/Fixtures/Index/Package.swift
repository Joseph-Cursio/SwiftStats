// swift-tools-version: 6.0
import PackageDescription

// The index collectors' fixture (M7): the T1 build, the index store, outskirts
// and the compiler's timings and warnings, every case in one package.
// `IndexCore` holds the USR join's kinds, protocols, references, test-only and
// dead code, keys and types, and warnings; `index-kit` is a dashed target in a
// library product (C99 `index_kit`), `index-support` a dashed library in no
// product (C99 `index_support`); `IndexApp` has top-level code, `IndexTool` an
// `@main` type. `index-kit` and `index-support` share `Sources/Kits`, each
// naming its files, so the recording can move `Relay.swift` from one target to
// the other by editing these two lines alone (a stale unit of a file that
// still exists). `../IndexDep` is a local path dependency.
// `Scripts/record-index-fixture.sh` builds a copy and records what the tools
// print into `Recorded/index/`.
let package = Package(
    name: "IndexFixture",
    platforms: [.macOS(.v14)],
    products: [
        .library(name: "IndexCore", targets: ["IndexCore"]),
        .library(name: "IndexKit", targets: ["index-kit"])
    ],
    dependencies: [.package(path: "../IndexDep")],
    targets: [
        .target(name: "IndexCore", dependencies: [.product(name: "IndexDepKit", package: "IndexDep")]),
        .target(name: "index-kit", path: "Sources/Kits", sources: ["Kit.swift", "Relay.swift"]),
        .target(name: "index-support", path: "Sources/Kits", sources: ["Support.swift"]),
        .executableTarget(name: "IndexApp", dependencies: ["IndexCore", "index-support"]),
        .executableTarget(name: "IndexTool"),
        .testTarget(name: "IndexCoreTests", dependencies: ["IndexCore", "index-support", "index-kit"]),
        .testTarget(name: "IndexXCTests", dependencies: ["IndexCore"])
    ]
)
