// swift-tools-version: 6.0
import PackageDescription

// The coverage collector's fixture (M5): a library and two test targets,
// one of whose names shares the words `Swift` and `Test` with SwiftPM's
// generated runner, so the runner's mangled name substitutes them. The
// library's files hold the mapping's cases (accessors, nesting, overloads,
// `#if`, a byte order mark, attachments); `Exe` is an executable the tests
// import, `Unlinked` a library no test links, and `Nested/Helper` a
// nested package the library depends on.
// `Scripts/record-coverage-fixture.sh` builds a copy and records what the
// tools print into `Recorded/`.
let package = Package(
    name: "CoverageProbe",
    platforms: [.macOS(.v14)],
    dependencies: [.package(path: "Nested/Helper")],
    targets: [
        .target(name: "Probe", dependencies: [.product(name: "Helper", package: "Helper")]),
        .target(name: "Unlinked"),
        .executableTarget(name: "Exe"),
        .testTarget(name: "ProbeTests", dependencies: ["Probe", "Exe"]),
        .testTarget(name: "SwiftTestKitTests", dependencies: ["Probe"])
    ]
)
