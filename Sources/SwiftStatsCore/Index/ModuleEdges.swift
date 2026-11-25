//
//  ModuleEdges.swift
//  SwiftStatsCore
//
//  The package targets' module edges (M7, design §4.2). A `package` edge
//  from one target to another counts the distinct reference occurrences
//  (file, line, column, USR, roles) in the first's files whose USR is
//  defined in the other's, and the first's files importing the other: the
//  distinct main files of its kept and variant units whose unit
//  dependencies name the other. A `dependency` edge goes to a non-system
//  module that isn't the package's, named by such a unit dependency, with
//  its importing files and no reference count, since dependency units'
//  records aren't read. An edge exists when either count isn't zero.
//

/// Builds the module edges of a snapshot.
enum ModuleEdges {
    /// A reference occurrence as an edge counts it.
    private struct Counted: Hashable {
        /// Its file.
        let file: String
        /// Its line.
        let line: Int
        /// Its column.
        let column: Int
        /// Its symbol.
        let usr: String
        /// Its roles.
        let roles: UInt64
    }

    /// An edge's end and kind, before it is counted.
    private struct End: Hashable {
        /// The target it starts at.
        let from: String
        /// The module it points at.
        let destination: String
        /// What it points at.
        let kind: IndexModuleEdge.Kind
    }

    /// The edges of `snapshot`'s read units and of `facts`' references,
    /// each referencing file's target in `targets`, the package's targets
    /// named `packageTargets`, sorted by source, then destination.
    static func edges(
        of snapshot: IndexSnapshot,
        facts: OccurrenceFacts,
        targets: [String: String],
        packageTargets: Set<String>
    ) -> [IndexModuleEdge] {
        var references: [End: Set<Counted>] = [:]
        for located in facts.references {
            guard let source = targets[located.file] else {
                continue
            }
            let occurrence = located.occurrence
            for destination in facts.definitionTargets[occurrence.usr, default: []] where destination != source {
                let end = End(from: source, destination: destination, kind: .package)
                references[end, default: []].insert(Counted(
                    file: located.file,
                    line: occurrence.line,
                    column: occurrence.column,
                    usr: occurrence.usr,
                    roles: occurrence.roles
                ))
            }
        }
        var files: [End: Set<String>] = [:]
        for unit in snapshot.readUnits where unit.isPackageModule && isPackagePath(unit.path) {
            for dependency in unit.moduleDependencies where dependency.isSystem == false {
                let kind: IndexModuleEdge.Kind = packageTargets.contains(dependency.module) ? .package : .dependency
                if dependency.module != unit.module {
                    files[End(from: unit.module, destination: dependency.module, kind: kind), default: []]
                        .insert(unit.path)
                }
            }
        }
        var edges: [[String]: IndexModuleEdge] = [:]
        for end in Set(references.keys).union(files.keys) {
            let fileCount = files[end]?.count ?? 0
            let edge = IndexModuleEdge(
                fromModule: end.from,
                toModule: end.destination,
                kind: end.kind,
                references: end.kind == .package ? references[end]?.count ?? 0 : nil,
                files: fileCount
            )
            edges[[end.from, end.destination]] = edge
        }
        return edges.sorted { CodePointOrder.precedes($0.key, $1.key) }.map(\.value)
    }

    /// Whether `path` is a unit's main file in the package: neither empty
    /// nor absolute (outside the root).
    private static func isPackagePath(_ path: String) -> Bool {
        path.isEmpty == false && path.hasPrefix("/") == false
    }
}
