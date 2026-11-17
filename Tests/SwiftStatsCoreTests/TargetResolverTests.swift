import Foundation
@testable import SwiftStatsCore
import Testing

@Suite("TargetResolver")
struct TargetResolverTests {
    private static func target(_ name: String, type: String, path: String, sources: [String]) -> DescribedTarget {
        DescribedTarget(name: name, type: type, moduleType: "SwiftTarget", path: path, sources: sources)
    }

    @Test("files are joined to the target path, Swift only, sorted; targets sorted by name")
    func mapping() {
        let package = DescribedPackage(name: "Pkg", targets: [
            Self.target("Lib", type: "library", path: "Sources/Lib", sources: ["B.swift", "A.swift", "shim.c"]),
            Self.target("LibTests", type: "test", path: "Tests/LibTests", sources: ["T.swift"]),
            Self.target("CLib", type: "library", path: "Sources/CLib", sources: ["shim.c"]),
            Self.target("Bin", type: "binary", path: "", sources: [])
        ])

        let targets = TargetResolver.resolve(package)

        #expect(targets.map(\.name) == ["Lib", "LibTests"])
        #expect(targets[0].files == ["Sources/Lib/A.swift", "Sources/Lib/B.swift"])
        #expect(targets[0].isTest == false)
        #expect(targets[1].isTest)
    }

    @Test("a target rooted at the package gives paths with no ./ prefix")
    func rootTarget() {
        let package = DescribedPackage(name: "Pkg", targets: [
            Self.target("Tool", type: "executable", path: ".", sources: ["main.swift", "./Sub/../Util.swift"])
        ])

        let target = TargetResolver.resolve(package)[0]

        #expect(target.path.isEmpty)
        #expect(target.files == ["Util.swift", "main.swift"])
    }

    @Test("SwiftPM's own file choice is used: resources, symlinks, bundles, Sources-based tests")
    func againstSwiftPM() throws {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("TargetResolverTests-\(UUID().uuidString)")
        defer { try? FileManager.default.removeItem(at: root) }
        let files = [
            "Sources/Lib/A.swift",
            "Sources/Lib/Fixtures/Copied.swift",
            "Sources/Lib/Lib.docc/Step.swift",
            "Sources/Lib/Extra.bundle/Kept.swift",
            "Sources/Lib/bundle/AlsoKept.swift",
            "Shared/Linked.swift",
            "Sources/LibTests/T.swift"
        ]
        for file in files {
            let url = root.appendingPathComponent(file)
            try FileManager.default.createDirectory(
                at: url.deletingLastPathComponent(),
                withIntermediateDirectories: true
            )
            try Data("let value = 1\n".utf8).write(to: url)
        }
        try FileManager.default.createSymbolicLink(
            atPath: root.appendingPathComponent("Sources/Lib/Linked").path,
            withDestinationPath: "../../Shared"
        )
        let manifest = """
        // swift-tools-version: 5.9
        import PackageDescription
        let package = Package(name: "Probe", targets: [
            .target(name: "Lib", resources: [.copy("Fixtures")]),
            .testTarget(name: "LibTests", dependencies: ["Lib"])
        ])
        """
        try Data(manifest.utf8).write(to: root.appendingPathComponent("Package.swift"))

        let targets = TargetResolver.resolve(try SwiftPMPackageDescriber().describePackage(at: root))

        #expect(targets.map(\.name) == ["Lib", "LibTests"])
        #expect(targets[0].files == [
            "Sources/Lib/A.swift",
            "Sources/Lib/Extra.bundle/Kept.swift",
            "Sources/Lib/Linked/Linked.swift",
            "Sources/Lib/bundle/AlsoKept.swift"
        ])
        #expect(targets[1].files == ["Sources/LibTests/T.swift"])
    }

    @Test("path normalisation drops . and empty segments and applies ..")
    func normalisation() {
        #expect(TargetResolver.normalised(".").isEmpty)
        #expect(TargetResolver.normalised("./Sources//Lib/") == "Sources/Lib")
        #expect(TargetResolver.normalised("Sources/Lib/Sub/../A.swift") == "Sources/Lib/A.swift")
    }
}
