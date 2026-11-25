//
//  MarkdownIndex+Coupling.swift
//  SwiftStatsCore
//
//  The coupling part of the report's Build and index section (M7, design
//  §4, §10.1): the module edges with their references and importing files
//  (no manifest marks), the production types other production modules
//  reference, most referenced first, and the USR type cycles with their
//  members, each with the sentence its empty state reads.
//

extension MarkdownIndex {
    /// The types with cross-module fan-in the section lists.
    static let listedTypes = 20

    /// The module edges, the types with cross-module fan-in and the type
    /// cycles.
    static func coupling(_ index: IndexReport) -> [String] {
        var lines = ["Module edges:", ""] + moduleEdges(index.moduleEdges)
        lines += ["", "Types referenced from other production modules:", ""] + fanIn(index.types)
        lines += ["", "Type cycles:", ""] + cycles(index.types)
        return lines
    }

    /// One row per module edge.
    private static func moduleEdges(_ edges: [IndexModuleEdge]) -> [String] {
        let header = ["From", "To", "Kind", "References", "Importing files"]
        return MarkdownList.lines(edges, header: header, empty: "No module edges.") { edge in
            [
                edge.fromModule,
                edge.toModule,
                edge.kind.rawValue,
                MarkdownNumber.optional(edge.references),
                String(edge.files)
            ]
        }
    }

    /// The production types with references from other production
    /// modules, most first, then by test referrers.
    private static func fanIn(_ types: [IndexTypeRow]) -> [String] {
        let referenced = types.filter { $0.referrersOtherModules > 0 }.sorted { lhs, rhs in
            if lhs.referrersOtherModules != rhs.referrersOtherModules {
                return lhs.referrersOtherModules > rhs.referrersOtherModules
            }
            if lhs.referrersTests != rhs.referrersTests {
                return lhs.referrersTests > rhs.referrersTests
            }
            return (lhs.module, lhs.typePath, lhs.typeFile ?? "") < (rhs.module, rhs.typePath, rhs.typeFile ?? "")
        }
        let header = ["Type", "Other modules", "Same module", "Tests"]
        let empty = "No type is referenced from another production module."
        return MarkdownList.lines(referenced, limit: listedTypes, header: header, empty: empty) { type in
            [
                name(type),
                String(type.referrersOtherModules),
                String(type.referrersSameModule),
                String(type.referrersTests)
            ]
        }
    }

    /// One row per USR type cycle, with its members.
    private static func cycles(_ types: [IndexTypeRow]) -> [String] {
        let members = Dictionary(grouping: types.filter { $0.cycle != nil }) { $0.cycle ?? 0 }
        let numbers = members.keys.sorted()
        return MarkdownList.lines(numbers, header: ["Cycle", "Types"], empty: "No type cycles.") { cycle in
            [String(cycle), (members[cycle] ?? []).map(name).joined(separator: ", ")]
        }
    }

    /// A type as the section names it: its target and path, with its file
    /// when it is file-scoped.
    private static func name(_ type: IndexTypeRow) -> String {
        "`\(type.module)::\(type.typePath)`" + (type.typeFile.map { " (\($0))" } ?? "")
    }
}
