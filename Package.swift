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
        )
    ],
    targets: [
        .target(
            name: "SwiftStatsCore",
            dependencies: [
                .product(name: "SwiftSyntax", package: "swift-syntax"),
                .product(name: "SwiftParser", package: "swift-syntax"),
                .product(name: "SwiftCodeMetrics", package: "SwiftCodeMetrics"),
                .product(name: "Yams", package: "Yams")
            ],
            swiftSettings: kSwiftSettings
        ),
        .executableTarget(
            name: "swiftstats",
            dependencies: [
                "SwiftStatsCore",
                .product(name: "ArgumentParser", package: "swift-argument-parser")
            ],
            swiftSettings: kSwiftSettings
        ),
        .testTarget(
            name: "SwiftStatsCoreTests",
            dependencies: ["SwiftStatsCore"],
            swiftSettings: kSwiftSettings
        )
    ]
)
