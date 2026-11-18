//
//  DependencyGraphAdapter.swift
//  SwiftStatsCore
//
//  The resolved dependency graph from `swift package show-dependencies
//  --format json` (PRD §7.14). That command resolves dependencies, which
//  may need the network, so it runs only when the package is already
//  resolved, or has no dependencies to resolve.
//

import Foundation

/// The `dependencies` collector.
enum DependencyGraphAdapter {
    /// One node of `show-dependencies`' tree.
    struct Node: Decodable {
        let identity: String
        let url: String?
        let path: String?
        let version: String?
        let dependencies: [Self]
    }

    /// The collector's name.
    static let name = "dependencies"
    /// The command's arguments after `swift`.
    static let arguments = ["package", "show-dependencies", "--format", "json"]

    /// The graph of the package at `root`, run with `swift` when it is resolved.
    static func run(
        swift: ToolResolution,
        root: URL,
        direct: [DescribedDependency]
    ) -> (status: CollectorStatus, graph: ResolvedGraph?) {
        let options = [arguments.joined(separator: " ")]
        let workspace = root.appendingPathComponent(".build/workspace-state.json")
        guard direct.isEmpty == false else {
            let status = CollectorStatus(name: name, state: .ran, version: nil, reason: nil, options: [])
            return (status, ResolvedGraph(packages: []))
        }
        guard FileManager.default.fileExists(atPath: workspace.path) else {
            let reason = "dependencies aren't resolved (no .build/workspace-state.json); "
                + "run `swift package resolve` first, since resolving may need the network"
            return (CollectorStatus(name: name, state: .skipped, version: nil, reason: reason, options: []), nil)
        }
        switch swift {
        case .skip(let reason):
            return (CollectorStatus(name: name, state: .skipped, version: nil, reason: reason, options: []), nil)

        case .found(let executable):
            do {
                let output = try ProcessRunner.run(executable: executable.path, arguments: arguments, in: root)
                let graph = ResolvedGraph(packages: try flatten(decode(output), direct: Set(direct.map(\.identity))))
                let status = CollectorStatus(name: name, state: .ran, version: nil, reason: nil, options: options)
                return (status, graph)
            } catch {
                let failed = AdapterResult.failed(name, error: error, options: options).status
                return (failed, nil)
            }
        }
    }

    /// The root node in `data`, skipping anything printed before the JSON.
    static func decode(_ data: Data) throws -> Node {
        let start = data.firstIndex(of: UInt8(ascii: "{")) ?? data.startIndex
        do {
            return try JSONDecoder().decode(Node.self, from: data[start...])
        } catch {
            throw AdapterError.unreadableOutput(name, String(describing: error))
        }
    }

    /// Every package below `root`, once each, sorted by identity.
    static func flatten(_ root: Node, direct: Set<String>) -> [ResolvedDependency] {
        var packages: [String: ResolvedDependency] = [:]
        var pending = root.dependencies
        while let node = pending.popLast() {
            pending += node.dependencies
            guard packages[node.identity] == nil else {
                continue
            }
            packages[node.identity] = ResolvedDependency(
                identity: node.identity,
                location: node.url ?? node.path ?? node.identity,
                version: node.version ?? "unspecified",
                direct: direct.contains(node.identity),
                dependencies: Set(node.dependencies.map(\.identity)).sorted()
            )
        }
        return packages.values.sorted { $0.identity < $1.identity }
    }
}
