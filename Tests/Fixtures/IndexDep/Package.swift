// swift-tools-version: 6.0
import PackageDescription

// The Index fixture's local path dependency (M7): a package outside the
// fixture's root, so its units are another package's, its timings lie outside
// the root, and its warning (SwiftPM doesn't suppress a path dependency's) is
// dropped as outside the root.
let package = Package(
    name: "IndexDep",
    platforms: [.macOS(.v14)],
    products: [.library(name: "IndexDepKit", targets: ["IndexDepKit"])],
    targets: [.target(name: "IndexDepKit")]
)
