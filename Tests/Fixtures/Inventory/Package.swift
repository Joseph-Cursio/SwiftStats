// swift-tools-version: 6.0
// A fixture for SwiftStats' M1b counts: risk markers, API surface and the
// test inventory, each checked by hand in InventoryFixtureTests.
import PackageDescription

let package = Package(
    name: "Inventory",
    targets: [
        .target(name: "Inventory"),
        .testTarget(name: "InventoryTests", dependencies: ["Inventory"])
    ]
)
