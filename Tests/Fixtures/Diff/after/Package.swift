// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "Shapes",
    targets: [
        .target(name: "Shapes"),
        .target(name: "Glossary"),
        .target(name: "Spelling", dependencies: ["Glossary"])
    ]
)
