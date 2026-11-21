// swift-tools-version: 6.0
import PackageDescription

// A nested package under the fixture's root: its files are in the export,
// but belong to no target of the fixture.
let package = Package(
    name: "Helper",
    platforms: [.macOS(.v14)],
    products: [.library(name: "Helper", targets: ["Helper"])],
    targets: [.target(name: "Helper")]
)
