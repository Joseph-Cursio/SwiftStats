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
        .package(
            url: "https://github.com/apple/swift-argument-parser.git",
            from: "1.5.0"
        )
    ],
    targets: [
        .target(
            name: "SwiftStatsCore",
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
