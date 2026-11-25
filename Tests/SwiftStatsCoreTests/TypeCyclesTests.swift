@testable import SwiftStatsCore
import Testing

/// USR type cycles over synthetic graphs (M7, design §4.3): Tarjan's
/// strongly connected components of two or more types, numbered the
/// largest first, then by first member.
@Suite("Type cycles")
struct TypeCyclesTests {
    /// A type in module `M` whose path is its name.
    private static func identity(_ name: String) -> TypeIdentity {
        TypeIdentity(module: "M", typePath: name, typeFile: "")
    }

    @Test("""
        components of two or more types are cycles, numbered the largest first, then by first member; a self \
        edge, a chain and a lone type are none
        """)
    func numbering() {
        let edges: [String: Set<String>] = [
            "E": ["F"], "F": ["E"],
            "A": ["B"], "B": ["C"], "C": ["A", "D"],
            "Y": ["Z"], "Z": ["Y"],
            "S": ["S"], "P": ["Q"], "Q": ["R"]
        ]
        let nodes = ["A", "B", "C", "D", "E", "F", "P", "Q", "R", "S", "Y", "Z", "L"]
        let cycles = TypeCycles(nodes: nodes.reversed(), edges: edges, identity: Self.identity)
        #expect(cycles.cycles == [["A", "B", "C"], ["E", "F"], ["Y", "Z"]])
        #expect(cycles.numbers == ["A": 1, "B": 1, "C": 1, "E": 2, "F": 2, "Y": 3, "Z": 3])
    }

    @Test("members are ordered by identity, so a file-scoped type sorts by its file after the plain one")
    func identityOrder() {
        let identities = [
            "u1": TypeIdentity(module: "M", typePath: "Book", typeFile: "b.swift"),
            "u2": TypeIdentity(module: "M", typePath: "Book", typeFile: ""),
            "u3": TypeIdentity(module: "L", typePath: "Zed", typeFile: "")
        ]
        let cycles = TypeCycles(
            nodes: ["u1", "u2", "u3"],
            edges: ["u1": ["u2"], "u2": ["u3"], "u3": ["u1"]]
        ) { identities[$0] ?? .unknown }
        #expect(cycles.cycles == [["u3", "u2", "u1"]])
    }

    @Test("""
        an edge into a component already found, a cycle or a lone type finished earlier, joins nothing to it: \
        the later cycle is still found and numbered
        """)
    func crossEdges() {
        let edges: [String: Set<String>] = [
            "A": ["B"], "B": ["A"],
            "C": ["A", "D"], "D": ["C"],
            "E": ["L"], "L": [],
            "F": ["L", "G"], "G": ["F", "E"]
        ]
        let cycles = TypeCycles(nodes: ["A", "B", "C", "D", "E", "F", "G", "L"], edges: edges, identity: Self.identity)
        #expect(cycles.cycles == [["A", "B"], ["C", "D"], ["F", "G"]])
        #expect(cycles.numbers == ["A": 1, "B": 1, "C": 2, "D": 2, "F": 3, "G": 3])
    }

    @Test("a chain of ten thousand types, ending in a two-type cycle, is searched without deep recursion")
    func deepChain() {
        let count = 10_000
        let names = (0 ..< count).map { "T\($0)" }
        var edges: [String: Set<String>] = [:]
        for (index, name) in names.enumerated().dropLast() {
            edges[name] = [names[index + 1]]
        }
        edges[names[count - 1]] = [names[count - 2]]
        let cycles = TypeCycles(nodes: names, edges: edges, identity: Self.identity)
        #expect(cycles.cycles == [[names[count - 2], names[count - 1]]])
        #expect(cycles.numbers.count == 2)
    }

    @Test("a cycle through ten thousand types is found without deep recursion")
    func deepCycle() {
        let count = 10_000
        let names = (0 ..< count).map { "T\($0)" }
        var edges: [String: Set<String>] = [:]
        for (index, name) in names.enumerated() {
            edges[name] = [names[(index + 1) % count]]
        }
        let cycles = TypeCycles(nodes: names, edges: edges, identity: Self.identity)
        #expect(cycles.cycles.count == 1 && cycles.cycles.first?.count == count)
        #expect(cycles.numbers.count == count)
    }
}
