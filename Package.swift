// swift-tools-version: 6.2
import PackageDescription

let kSwiftSettings: [SwiftSetting] = [
    .swiftLanguageMode(.v6)
]

let kPackage = Package(
    name: "SwiftStats",
    platforms: [.macOS(.v14)],
    products: [
        .executable(
            name: "swiftstats",
            targets: ["swiftstats"]
        ),
        .library(
            name: "SwiftStatsCore",
            targets: ["SwiftStatsCore"]
        )
    ],
    dependencies: [
        // Pinned exactly to match SwiftEffectInference, SwiftProjectLint and
        // SwiftInferProperties, so SwiftEffectInference can be linked (PRD D3).
        .package(
            url: "https://github.com/swiftlang/swift-syntax.git",
            exact: "603.0.2"
        ),
        .package(
            url: "https://github.com/apple/swift-argument-parser.git",
            from: "1.5.0"
        ),
        // Complexity (PRD §7.3), shared with SwiftProjectLint; pinned to a release (D3).
        .package(
            url: "https://github.com/Joseph-Cursio/SwiftCodeMetrics.git",
            exact: "0.3.0"
        ),
        // `.swiftstats.yml` (PRD §10.1), as SwiftMutator reads its configuration.
        .package(
            url: "https://github.com/jpsim/Yams.git",
            from: "6.1.0"
        ),
        // The snapshot store (PRD §9, D9).
        .package(
            url: "https://github.com/groue/GRDB.swift.git",
            from: "7.12.0"
        ),
        // Side effects (PRD §7.10), linked in process. Pinned by revision,
        // the one SwiftProjectLint and SwiftInferProperties pin (the package
        // has no tags), so nothing can depend on SwiftStatsCore by version.
        // Keep `EffectInferenceRevision.pinned` equal to it.
        .package(
            url: "https://github.com/Joseph-Cursio/SwiftEffectInference.git",
            revision: "ba3624d754c3c9150c946f66468c2c356be3e7e0"
        ),
        // The index store reader (PRD §6.1, D3), pinned to the tag of the toolchain
        // SwiftStats is built with (swift-6.4.2-RELEASE); only the IndexStore product
        // is linked, never IndexStoreDB (no C++, no LMDB database, no name clash).
        // Keep `IndexStoreReader.pinned` equal to it.
        .package(
            url: "https://github.com/swiftlang/indexstore-db.git",
            revision: "64aa0b26913249c4e7c21d351a215fba02702003"
        )
    ],
    targets: [
        .target(
            name: "SwiftStatsCore",
            dependencies: [
                .product(name: "SwiftSyntax", package: "swift-syntax"),
                .product(name: "SwiftParser", package: "swift-syntax"),
                .product(name: "SwiftCodeMetrics", package: "SwiftCodeMetrics"),
                .product(name: "Yams", package: "Yams"),
                .product(name: "GRDB", package: "GRDB.swift"),
                .product(name: "SwiftEffectInference", package: "SwiftEffectInference"),
                .product(name: "IndexStore", package: "indexstore-db")
            ],
            swiftSettings: kSwiftSettings
        ),
        // SwiftStats' own build identity (PRD §6.2), embedded at build time.
        // Only the executable and the tests depend on it, never
        // SwiftStatsCore, so a package using the library doesn't run the plugin.
        .target(
            name: "SwiftStatsBuildInfo",
            swiftSettings: kSwiftSettings,
            plugins: ["BuildInfoPlugin"]
        ),
        .plugin(
            name: "BuildInfoPlugin",
            capability: .buildTool()
        ),
        .executableTarget(
            name: "swiftstats",
            dependencies: [
                "SwiftStatsCore",
                "SwiftStatsBuildInfo",
                .product(name: "ArgumentParser", package: "swift-argument-parser")
            ],
            swiftSettings: kSwiftSettings
        ),
        .testTarget(
            name: "SwiftStatsCoreTests",
            dependencies: ["SwiftStatsCore", "SwiftStatsBuildInfo"],
            swiftSettings: kSwiftSettings
        )
    ]
)
