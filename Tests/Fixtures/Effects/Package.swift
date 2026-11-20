// swift-tools-version: 6.0
// A fixture for SwiftStats' side-effect facts (M4): declared, unknown and
// conflicting tiers, purity verdicts, strict body inference, placement and
// value shape, each checked by hand in EffectCollectorTests. It is parsed,
// never built: the attributes and the types it calls are not declared.
import PackageDescription

let package = Package(
    name: "Effects",
    targets: [
        .target(name: "Effects")
    ]
)
