import Foundation
@testable import SwiftStatsCore
import Testing

/// Direct dependencies, pins and the resolved graph (PRD §7.14).
@Suite("Dependencies")
struct DependencyTests {
    private static let describe = """
    {"name": "Probe", "targets": [], "dependencies": [
      {"identity": "swift-numerics", "type": "sourceControl", "url": "https://github.com/apple/swift-numerics.git",
       "requirement": {"range": [{"lower_bound": "1.0.0", "upper_bound": "2.0.0"}]}},
      {"identity": "swift-syntax", "type": "sourceControl", "url": "https://github.com/swiftlang/swift-syntax.git",
       "requirement": {"exact": ["603.0.2"]}},
      {"identity": "tool", "type": "sourceControl", "url": "https://example.com/tool.git",
       "requirement": {"branch": ["main"]}},
      {"identity": "pinned", "type": "sourceControl", "url": "https://example.com/pinned.git",
       "requirement": {"revision": ["abc123"]}},
      {"identity": "local", "type": "fileSystem", "path": "/work/local"},
      {"identity": "scope.name", "type": "registry", "requirement": {"exact": ["1.0.0"]}}
    ]}
    """

    /// A `show-dependencies` node.
    private static func node(_ identity: String, _ version: String, _ children: [String]) -> String {
        """
        {"identity": "\(identity)", "name": "\(identity)", "url": "https://example.com/\(identity).git",
         "version": "\(version)", "path": "/tmp/\(identity)", "traits": [],
         "dependencies": [\(children.joined(separator: ","))]}
        """
    }

    @Test("describe's requirements read as ranges, exact versions, branches and revisions")
    func directDependencies() throws {
        let package = try JSONDecoder().decode(DescribedPackage.self, from: Data(Self.describe.utf8))

        #expect(package.dependencies.map(\.requirement) == [
            "1.0.0..<2.0.0", "exact 603.0.2", "branch main", "revision abc123", nil, "exact 1.0.0"
        ])
        #expect(package.dependencies.map(\.location) == [
            "https://github.com/apple/swift-numerics.git", "https://github.com/swiftlang/swift-syntax.git",
            "https://example.com/tool.git", "https://example.com/pinned.git", "/work/local", "scope.name"
        ])
        let bare = Data(#"{"name": "A", "targets": []}"#.utf8)
        let noDependencies = try JSONDecoder().decode(DescribedPackage.self, from: bare)
        #expect(noDependencies.dependencies.isEmpty)
    }

    @Test("Package.resolved pins read from versions 1 and 2, sorted")
    func pins() throws {
        let current = """
        {"pins": [
          {"identity": "yams", "kind": "remoteSourceControl", "location": "https://github.com/jpsim/Yams.git",
           "state": {"revision": "a27b", "version": "6.2.2"}},
          {"identity": "tool", "kind": "remoteSourceControl", "location": "https://example.com/tool.git",
           "state": {"branch": "main", "revision": "ffee"}}
        ], "version": 3}
        """
        let legacy = """
        {"object": {"pins": [{"package": "Numerics", "repositoryURL": "https://github.com/apple/swift-numerics.git",
          "state": {"branch": null, "revision": "0a5b", "version": "1.0.2"}}]}, "version": 1}
        """

        let pins = try PackageResolvedReader.pins(in: Data(current.utf8))
        #expect(pins.map(\.identity) == ["tool", "yams"])
        #expect(pins.map(\.version) == [nil, "6.2.2"])
        #expect(pins.map(\.branch) == ["main", nil])
        let old = try PackageResolvedReader.pins(in: Data(legacy.utf8))
        let numerics = DependencyPin(
            identity: "swift-numerics",
            location: "https://github.com/apple/swift-numerics.git",
            version: "1.0.2",
            branch: nil,
            revision: "0a5b"
        )
        #expect(old == [numerics])
    }

    @Test("the graph lists each package once, marking the direct ones")
    func flatten() throws {
        let shared = Self.node("shared", "1.0.0", [])
        let tree = Self.node("root", "unspecified", [
            Self.node("left", "2.0.0", [shared]), Self.node("right", "3.1.0", [shared])
        ])
        let root = try DependencyGraphAdapter.decode(Data(("Fetching…\n" + tree).utf8))
        let graph = DependencyGraphAdapter.flatten(root, direct: ["left", "right"])

        #expect(graph.map(\.identity) == ["left", "right", "shared"])
        #expect(graph.map(\.direct) == [true, true, false])
        #expect(graph.map(\.dependencies) == [["shared"], ["shared"], []])
        #expect(graph.map(\.version) == ["2.0.0", "3.1.0", "1.0.0"])
    }

    @Test("the graph runs only once resolved; a package with no dependencies needs no run")
    func whenItRuns() throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent("Deps-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let dependency = DescribedDependency(identity: "left", type: "sourceControl", location: "x", requirement: nil)
        let swift = try FakeTool.make(
            outputs: [Self.node("root", "unspecified", [Self.node("left", "2.0.0", [])])],
            errorText: "",
            statuses: [0]
        )

        let none = DependencyGraphAdapter.run(swift: .found(swift), root: directory, direct: [])
        let unresolved = DependencyGraphAdapter.run(swift: .found(swift), root: directory, direct: [dependency])
        try FileManager.default.createDirectory(
            at: directory.appendingPathComponent(".build"),
            withIntermediateDirectories: true
        )
        let workspace = directory.appendingPathComponent(".build/workspace-state.json")
        try "{}".write(to: workspace, atomically: true, encoding: .utf8)
        let resolved = DependencyGraphAdapter.run(swift: .found(swift), root: directory, direct: [dependency])

        #expect(none.status.state == .ran)
        #expect(none.graph == ResolvedGraph(packages: []))
        #expect(unresolved.status.state == .skipped)
        #expect(unresolved.graph == nil)
        #expect(resolved.status.state == .ran)
        #expect(resolved.graph?.packages.map(\.identity) == ["left"])
        let command = "package --disable-automatic-resolution show-dependencies --format json"
        #expect(FakeTool.arguments(of: swift) == [command])
    }

    @Test("a disabled collector is skipped for that reason, with or without dependencies")
    func disabled() {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent("Deps-\(UUID().uuidString)")
        let reason = "disabled by collectors.dependencies.enabled"
        let dependency = DescribedDependency(identity: "left", type: "sourceControl", location: "x", requirement: nil)

        let none = DependencyGraphAdapter.run(swift: .skip(reason), root: directory, direct: [])
        let some = DependencyGraphAdapter.run(swift: .skip(reason), root: directory, direct: [dependency])

        #expect([none.status.state, some.status.state] == [.skipped, .skipped])
        #expect([none.status.reason, some.status.reason] == [reason, reason])
        #expect(none.graph == nil && some.graph == nil)
    }

    @Test("a Package.resolved that can't be read gives a warning, not an absent lockfile")
    func unreadableLockfile() throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent("Deps-\(UUID().uuidString)")
        // A directory where the file should be: present, but not readable as a file.
        try FileManager.default.createDirectory(
            at: directory.appendingPathComponent("Package.resolved"),
            withIntermediateDirectories: true
        )
        defer { try? FileManager.default.removeItem(at: directory) }

        let (lockfile, warning) = PackageResolvedReader.lockfile(root: directory)
        let (missing, noWarning) = PackageResolvedReader.lockfile(
            root: FileManager.default.temporaryDirectory.appendingPathComponent("Absent-\(UUID().uuidString)")
        )

        #expect(lockfile == nil)
        #expect(warning?.file == "Package.resolved")
        #expect(warning?.message.hasPrefix("not readable: ") == true)
        #expect(missing == nil && noWarning == nil)
    }
}
