import Foundation
import SwiftStatsCore
import Testing

@Suite("TargetResolver")
struct TargetResolverTests {
    private static func makePackage(files: [String]) throws -> URL {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("TargetResolverTests-\(UUID().uuidString)")
        for file in files {
            let url = root.appendingPathComponent(file)
            try FileManager.default.createDirectory(
                at: url.deletingLastPathComponent(),
                withIntermediateDirectories: true
            )
            try Data("// \(file)\n".utf8).write(to: url)
        }
        return root
    }

    private static func target(
        _ name: String,
        type: String = "regular",
        path: String? = nil,
        sources: [String] = [],
        exclude: [String] = []
    ) -> ManifestTarget {
        ManifestTarget(name: name, type: type, path: path, sources: sources, exclude: exclude)
    }

    @Test("default directories put regular targets under Sources and tests under Tests")
    func defaultDirectories() throws {
        let root = try Self.makePackage(files: [
            "Sources/Lib/A.swift",
            "Sources/Lib/Nested/B.swift",
            "Sources/Lib/readme.md",
            "Tests/LibTests/ATests.swift"
        ])
        defer { try? FileManager.default.removeItem(at: root) }
        let manifest = PackageManifest(name: "Pkg", targets: [
            Self.target("Lib"),
            Self.target("LibTests", type: "test")
        ])

        let targets = TargetResolver().resolve(manifest, packageRoot: root)

        #expect(targets.map(\.name) == ["Lib", "LibTests"])
        #expect(targets[0].files == ["Sources/Lib/A.swift", "Sources/Lib/Nested/B.swift"])
        #expect(targets[0].isTest == false)
        #expect(targets[1].files == ["Tests/LibTests/ATests.swift"])
        #expect(targets[1].isTest)
    }

    @Test("custom path, exclude and hidden directories are honoured")
    func customPathAndExclude() throws {
        let root = try Self.makePackage(files: [
            "Code/Core/Keep.swift",
            "Code/Core/Skip/Gone.swift",
            "Code/Core/.hidden/Hidden.swift",
            "Code/Core/Excluded.swift"
        ])
        defer { try? FileManager.default.removeItem(at: root) }
        let manifest = PackageManifest(name: "Pkg", targets: [
            Self.target("Core", path: "./Code/Core/", exclude: ["Skip", "Excluded.swift"])
        ])

        let targets = TargetResolver().resolve(manifest, packageRoot: root)

        #expect(targets.first?.path == "Code/Core")
        #expect(targets.first?.files == ["Code/Core/Keep.swift"])
    }

    @Test("an explicit sources list limits the files")
    func explicitSources() throws {
        let root = try Self.makePackage(files: [
            "Sources/Lib/In/A.swift",
            "Sources/Lib/Single.swift",
            "Sources/Lib/Out/B.swift"
        ])
        defer { try? FileManager.default.removeItem(at: root) }
        let manifest = PackageManifest(name: "Pkg", targets: [
            Self.target("Lib", sources: ["In", "Single.swift"])
        ])

        let targets = TargetResolver().resolve(manifest, packageRoot: root)

        #expect(targets.first?.files == ["Sources/Lib/In/A.swift", "Sources/Lib/Single.swift"])
    }

    @Test("a target nested in another's directory keeps its own files")
    func nestedTargets() throws {
        let root = try Self.makePackage(files: [
            "Sources/Outer/A.swift",
            "Sources/Outer/Inner/B.swift"
        ])
        defer { try? FileManager.default.removeItem(at: root) }
        let manifest = PackageManifest(name: "Pkg", targets: [
            Self.target("Outer"),
            Self.target("Inner", path: "Sources/Outer/Inner")
        ])

        let targets = TargetResolver().resolve(manifest, packageRoot: root)

        #expect(targets[0].files == ["Sources/Outer/A.swift"])
        #expect(targets[1].files == ["Sources/Outer/Inner/B.swift"])
    }

    @Test("binary and system targets and missing directories are skipped")
    func skippedTargets() throws {
        let root = try Self.makePackage(files: ["Sources/Lib/A.swift"])
        defer { try? FileManager.default.removeItem(at: root) }
        let manifest = PackageManifest(name: "Pkg", targets: [
            Self.target("Lib"),
            Self.target("Bin", type: "binary"),
            Self.target("CLib", type: "system"),
            Self.target("Missing")
        ])

        let targets = TargetResolver().resolve(manifest, packageRoot: root)

        #expect(targets.map(\.name) == ["Lib"])
    }

    @Test("Swift files inside resource bundles such as .docc are not sources")
    func bundlesSkipped() throws {
        let root = try Self.makePackage(files: [
            "Sources/Lib/A.swift",
            "Sources/Lib/Lib.docc/Resources/Step1.swift",
            "Sources/Lib/Demo.playground/Contents.swift"
        ])
        defer { try? FileManager.default.removeItem(at: root) }
        let manifest = PackageManifest(name: "Pkg", targets: [Self.target("Lib")])

        #expect(TargetResolver().resolve(manifest, packageRoot: root).first?.files == ["Sources/Lib/A.swift"])
    }
}
