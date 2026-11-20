//
//  MissingTemplateTests.swift
//  SwiftStatsCoreTests
//
//  Missing template (PRD §8) on the Ledger fixture: which functions the
//  shape filters keep, that a suggestion of any tier takes a function off
//  the list, the order by shape, then body lines, and that a plugin
//  target's functions, which SwiftInferProperties never indexes, stay out.
//

import Foundation
@testable import SwiftStatsCore
import Testing

@Suite("Missing template")
struct MissingTemplateTests {
    @Test("pure, value-shaped, shaped functions with no suggestion list by shape, then body lines, shortest first")
    func listed() throws {
        let signal = try SignalHarness.signal(.missingTemplate, of: try LedgerFixture.snapshot())

        #expect(signal.leftOut == nil)
        #expect(signal.items.map(\.subject) == [
            "Core::func negated(_: [Int]) -> [Int]",
            "Core::func outer(_: Int) -> Int",
            "Core::func parsed(_: String) throws -> String",
            "Core::func evens(in: [Int]) -> [Int]",
            "Core::Money::static func combined(_: Money, _: Money) -> Money",
            "Core::Money::func scaled(by: Int) -> Money",
            "Core::func isEven(_: Int) -> Bool"
        ])
        #expect(signal.items.map(\.effect?.shape) == [
            .endomorphism, .endomorphism, .endomorphism, .endomorphism, .binary, .selfReturning, .predicate
        ])
        #expect(signal.items.map(\.score) == signal.items.map { Double($0.function?.bodyLines ?? -1) })
        #expect(signal.items.map(\.score) == [1, 4, 4, 5, 1, 1, 1])
        #expect(signal.members.count == 7)
        let parsed = try #require(signal.items.first { $0.subject.contains("parsed") })
        #expect(parsed.effect?.purity == .pureButPartial)
        #expect(parsed.effect?.inferred == nil)
        #expect(parsed.function?.cognitive == 1)
    }

    @Test("a suggestion of any tier takes a function off the list; refuted, mutating, nested, generated code stay out")
    func pool() throws {
        let signal = try SignalHarness.signal(.missingTemplate, of: try LedgerFixture.snapshot())
        let subjects = Set(signal.items.map(\.subject))

        // The seven listed, and adding (Advisory), subtracting (Possible),
        // doubled (idempotence-lifted) and shifted (round-trip), which have
        // suggestions, and unshifted, shifted's partner.
        #expect(signal.candidates == 12)
        let absentees = [
            "adding", "subtracting", "doubled", "shifted", "unshifted", "logged", "reset", "inner", "label", "tripled",
            "twice"
        ]
        for absent in absentees {
            #expect(subjects.contains { $0.contains("func \(absent)(") } == false, "\(absent)")
        }
        // label(_:) is pure and value-shaped, but has no algebraic shape.
        #expect(signal.rule == MissingTemplate.rule
            + "; 1 pure, value-shaped functions have no algebraic shape and are left out")
    }

    @Test("a round trip takes its partner off the list as well as its subject")
    func partner() throws {
        let snapshot = try LedgerFixture.snapshot()
        let signal = try SignalHarness.signal(.missingTemplate, of: snapshot)
        let roundTrip = try #require(snapshot.candidates.first { $0.identity == "0x0000000000000013" })

        #expect(roundTrip.location?.owner == "Core::func shifted(_: Int) -> Int")
        #expect(roundTrip.partnerKey == "Core::func unshifted(_: Int) -> Int")
        #expect(signal.items.contains { $0.subject == "Core::func unshifted(_: Int) -> Int" } == false)
    }

    @Test("""
        functions in a plugin target, which SwiftInferProperties never indexes, are neither listed nor counted, \
        while the library's are
        """)
    func pluginLeftOut() throws {
        let shapes = """
            func tripled(_ value: Int) -> Int {
                value * 3
            }

            func named(_ value: Int) -> String {
                String(value)
            }
            """
        let files = PropertyHarness.files.merging([
            "Sources/Core/Shapes.swift": shapes,
            "Plugins/Plug/Plugin.swift": shapes.replacingOccurrences(of: "tripled", with: "doubled")
        ]) { _, new in new }
        let targets = PropertyHarness.targets.map { target in
            target.name == "Core"
                ? PropertyHarness.target("Core", "library", "Sources/Core", ["Shapes.swift", "Values.swift"])
                : target
        }
        let snapshot = try SignalHarness.stored(
            files,
            targets: targets,
            indexes: [
                "Core": PropertyHarness.emptyIndex,
                "Macros": PropertyHarness.emptyIndex,
                "Tool": PropertyHarness.emptyIndex
            ]
        )

        let signal = try SignalHarness.signal(.missingTemplate, of: snapshot)

        // The plugin's `doubled(_:)` and `named(_:)` mirror the library's
        // `tripled(_:)` and `named(_:)`, and count nowhere.
        #expect(signal.leftOut == nil)
        #expect(signal.items.allSatisfy { $0.file.hasPrefix("Plugins/") == false })
        #expect(signal.items.map(\.subject) == [
            "Core::Money::func secret(_: Int) -> Int @ Sources/Core/Values.swift",
            "Core::func tripled(_: Int) -> Int",
            "Core::func reduce(_: Int, _: Int) -> Int"
        ])
        #expect(signal.candidates == 3)
        #expect(signal.rule == MissingTemplate.rule
            + "; 5 pure, value-shaped functions have no algebraic shape and are left out")
    }

    @Test("the table shows the shape, purity, body lines and cognitive complexity")
    func table() throws {
        let signal = try SignalHarness.signal(.missingTemplate, of: try LedgerFixture.snapshot())
        let rows = SignalHarness.rows(signal)

        #expect(rows.first == "| # | Function | Score | Shape | Purity | Body lines | Cognitive | Member |")
        #expect(rows[4] == "| 3 | `func parsed(_: String) throws -> String` (Sources/Core/Shapes.swift:42) | 4 "
            + "| endomorphism | pure_but_partial | 4 | 1 | yes |")
        #expect(rows.last == "| 7 | `func isEven(_: Int) -> Bool` (Sources/Core/Shapes.swift:38) | 1 | predicate "
            + "| pure | 1 | 0 | yes |")
    }
}
