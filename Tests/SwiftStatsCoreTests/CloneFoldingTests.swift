//
//  CloneFoldingTests.swift
//  SwiftStatsCoreTests
//
//  Folding nested divergent classes (PRD §8): a member whose changed and
//  unchanged families lie within another's is listed only as part of it.
//

import Foundation
@testable import SwiftStatsCore
import Testing

@Suite("Divergent clone folding")
struct CloneFoldingTests {
    /// The file holding the twins.
    static let file = "Sources/Lib/Twins.swift"

    /// Two types with the same three methods, `name` first: each method at
    /// lines 2–5, 7–10 and 12–15 of its type, the second type from line 18.
    static func twins(_ names: [String]) -> String {
        names.map { type in
            let methods = ["head", "body", "tail"].enumerated().map { offset, method in
                """
                    func \(method)(_ value: Int) -> Int {
                        let step = value + \(offset + 1)
                        return step * \(offset + 2)
                    }
                """
            }
            return "struct \(type) {\n" + methods.joined(separator: "\n\n") + "\n}\n"
        }
        .joined(separator: "\n")
    }

    /// `text` with `method`'s step in the first type changed.
    static func changing(_ method: String, in text: String) -> String {
        let parts = text.components(separatedBy: "struct Lower")
        let offset = ["head", "body", "tail"].firstIndex(of: method).map { $0 + 1 } ?? 0
        let edited = parts[0].replacingOccurrences(of: "value + \(offset)\n", with: "value + \(offset * 10)\n")
        return ([edited] + parts.dropFirst()).joined(separator: "struct Lower")
    }

    @Test("a class nested in a listed one folds into it; with equal sets the more specific class stands")
    func strictNesting() throws {
        let repository = try CloneRepository()
        defer { repository.remove() }
        let text = Self.twins(["Upper", "Lower"])
        try repository.commit([Self.file: text], "Add twins", day: 0)
        // A run of `body` and `tail`, and `body` alone, exactly.
        let run = FakeClone(run: "--sequence", mass: 80, spans: [(Self.file, 7...15), (Self.file, 24...32)])
        let body = FakeClone(run: "default", mass: 40, spans: [(Self.file, 7...10), (Self.file, 24...27)], exact: true)
        try repository.report([run, body])
        try repository.scan()

        let bodyChanged = Self.changing("body", in: text)
        try repository.commit([Self.file: bodyChanged], "Change the body", day: 1)
        let equal = try repository.signal(.divergentClones, id: try repository.scan())
        try repository.commit([Self.file: Self.changing("tail", in: bodyChanged)], "Change the tail", day: 2)
        let nested = try repository.signal(.divergentClones, id: try repository.scan())

        // `body` is class 1 (its copy ends first), the run class 2.
        #expect(equal.candidates == 2)
        #expect(equal.items.map { $0.clone?.ordinal } == [1])
        #expect(equal.items.map { $0.clone?.divergence?.folded } == [[2]])
        #expect(equal.items.first?.score == 8)
        #expect(nested.items.map { $0.clone?.ordinal } == [2])
        #expect(nested.items.map { $0.clone?.divergence?.folded } == [[1]])
        #expect(nested.items.first?.subject == "Lib::Lower::func body(_: Int) -> Int")
        #expect(nested.items.first?.clone?.divergence?.unchanged.map(\.family) == [
            "Lib::Lower::func body(_: Int) -> Int", "Lib::Lower::func tail(_: Int) -> Int"
        ])
        #expect(nested.items.first?.score == 16)
        #expect(nested.rule.contains("; 1 classes nested in a listed one are folded into it"))
        #expect(SignalHarness.rows(equal).last?.contains("| exact | 2 | 8 | #2 | yes |") == true)
    }

    @Test("a member within two classes that don't hold each other folds into the one with the larger mass")
    func incomparableSupersets() throws {
        let repository = try CloneRepository()
        defer { repository.remove() }
        let text = Self.twins(["Upper", "Lower"])
        try repository.commit([Self.file: text], "Add twins", day: 0)
        let body = FakeClone(run: "default", mass: 40, spans: [(Self.file, 7...10), (Self.file, 24...27)])
        let bodyAndTail = FakeClone(run: "--sequence", mass: 80, spans: [(Self.file, 7...15), (Self.file, 24...32)])
        let headAndBody = FakeClone(run: "--type3", mass: 90, spans: [(Self.file, 2...10), (Self.file, 19...27)])
        try repository.report([body, bodyAndTail, headAndBody])
        try repository.scan()

        let changed = ["head", "body", "tail"].reduce(text) { Self.changing($1, in: $0) }
        try repository.commit([Self.file: changed], "Change every step", day: 1)
        let signal = try repository.signal(.divergentClones, id: try repository.scan())

        // Classes: head and body 1 (its copy starts first), body 2, body and tail 3.
        // Both runs score 16; the larger mass lists first and takes `body`.
        #expect(signal.candidates == 3)
        #expect(signal.items.map { $0.clone?.ordinal } == [1, 3])
        #expect(signal.items.map { $0.clone?.divergence?.folded } == [[2], []])
        #expect(signal.items.map(\.score) == [16, 16])
        #expect(signal.items.map { $0.clone?.pass } == [.nearMiss, .sequence])
    }
}
