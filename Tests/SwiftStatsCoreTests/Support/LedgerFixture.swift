//
//  LedgerFixture.swift
//  SwiftStatsCoreTests
//
//  A package for tool disagreement and missing template: functions whose
//  bodies SwiftEffectInference infers in each way (a heuristic or declared
//  non_idempotent callee, a shared signature, a shadowing or own
//  annotation, an idempotent callee, no callee), functions of each value
//  shape and of none, and suggestions on them, located by searching the
//  sources so the tests needn't count lines.
//

import Foundation
@testable import SwiftStatsCore

/// The tool-disagreement and missing-template package.
enum LedgerFixture {
    /// A Strong score.
    static let strong = 80
    /// A Likely score.
    static let likely = 40
    /// A Possible score.
    static let possible = 30
    /// The lowest Possible score that Verified evidence lifts.
    static let lowest = 25
    /// An Advisory row's score, in the Strong band.
    static let advisory = 90

    /// The ledger: what tool disagreement reads.
    static let ledger = """
    final class Ledger {
        let rows = RowStore()
        let cache = TotalsCache()

        func stage(_ amount: Int) -> Int {
            rows.insertRow(amount)
            return amount
        }

        func restage(_ amount: Int) -> Int {
            rows.insertRow(amount)
            return amount
        }

        func forward(_ amount: Int) -> Int {
            push(amount)
            return amount
        }

        @NonIdempotent
        func push(_ amount: Int) {
            rows.insertRow(amount)
        }

        @Idempotent
        func touch(_ amount: Int) -> Int {
            rows.insertRow(amount)
            return amount
        }

        func refreshed(_ key: String) -> String {
            cache.upsert(key)
            return key
        }

        func doubled(_ amount: Int) -> Int {
            amount * 2
        }

        var total: Int {
            rows.count
        }
    }

    struct First {
        let rows: RowStore

        func apply(_ amount: Int) -> Int {
            rows.insertRow(amount)
            return amount
        }
    }

    struct Second {
        let rows: RowStore

        func apply(_ amount: Int) -> Int {
            rows.insertRow(amount)
            return amount
        }
    }

    protocol Persisting {
        /// @lint.effect idempotent
        func persist() -> Int
    }

    struct Draft: Persisting {
        let rows: RowStore

        func persist() -> Int {
            rows.insertRow(1)
            return 1
        }
    }
    """

    /// Value shapes: what missing template reads.
    static let shapes = """
    struct Money {
        let cents: Int

        func scaled(by factor: Int) -> Money {
            Money(cents: cents * factor)
        }

        static func combined(_ lhs: Money, _ rhs: Money) -> Money {
            Money(cents: lhs.cents + rhs.cents)
        }

        func adding(_ other: Money) -> Money {
            Money(cents: cents + other.cents)
        }

        func subtracting(_ other: Money) -> Money {
            Money(cents: cents - other.cents)
        }

        mutating func reset() -> Money {
            self = Money(cents: 0)
            return self
        }
    }

    func evens(in values: [Int]) -> [Int] {
        var built: [Int] = []
        for value in values where value.isMultiple(of: 2) {
            built.append(value)
        }
        return built
    }

    func negated(_ values: [Int]) -> [Int] {
        values.map { -$0 }
    }

    func isEven(_ value: Int) -> Bool {
        value.isMultiple(of: 2)
    }

    func parsed(_ text: String) throws -> String {
        guard text.isEmpty == false else {
            throw ParseError.empty
        }
        return text
    }

    func logged(_ value: Int) -> Int {
        print(value)
        return value
    }

    func outer(_ value: Int) -> Int {
        func inner(_ other: Int) -> Int {
            other + 1
        }
        return inner(value)
    }

    func label(_ value: Money) -> String {
        String(value.cents)
    }

    func shifted(_ value: Int) -> Int {
        value + 1
    }

    func unshifted(_ value: Int) -> Int {
        value - 1
    }
    """

    /// A generated file: an idempotence row and a shape, both left out.
    static let generated = """
    // DO NOT EDIT
    func made(_ store: RowStore) -> Int {
        store.insertRow(1)
        return 1
    }

    func tripled(_ value: Int) -> Int {
        value * 3
    }
    """

    /// A test helper with a shape, left out.
    static let tests = """
    import Testing

    func twice(_ value: Int) -> Int {
        value * 2
    }

    @Test func twiceDoubles() {
        #expect(twice(1) == 2)
    }
    """

    /// The package's files.
    static let files = [
        "Sources/Core/Ledger.swift": ledger,
        "Sources/Core/Shapes.swift": shapes,
        "Sources/Core/Made.swift": generated,
        "Tests/CoreTests/TwiceTests.swift": tests
    ]

    /// The package's targets.
    static let targets = [
        PropertyHarness.target("Core", "library", "Sources/Core", ["Ledger.swift", "Made.swift", "Shapes.swift"]),
        PropertyHarness.target("CoreTests", "test", "Tests/CoreTests", ["TwiceTests.swift"])
    ]

    /// The suggestions: twelve in tool disagreement's pool (three listed,
    /// two on a shared signature, two declared, three on no production
    /// `func`, one with no inferred tier, one inferring another tier), a
    /// round-trip row outside it, Advisory and Possible rows on shapes, and a
    /// round-trip row on a shape whose partner is another.
    static var rows: [PropertyHarness.Row] {
        var unknown = PropertyHarness.Row(identity: "0x0000000000000009", location: "(unknown)", function: "(unknown)")
        unknown.template = "idempotence"
        var total = row("0x0000000000000008", "Ledger:var total", "idempotence", strong)
        total.computed = true
        total.function = "total"
        var blocked = row("0x0000000000000011", "Shapes:func adding", "commutativity", advisory)
        blocked.tier = "Advisory"
        blocked.blocker = "\"private\""
        var shifted = row("0x0000000000000013", "Shapes:func shifted", "round-trip", strong)
        shifted.extra = ", \"secondaryFunctionName\": \"unshifted(_:)\""
        return [
            row("0x0000000000000001", "Ledger:func stage", "idempotence", strong),
            row("0x0000000000000002", "Ledger:func restage", "replay-idempotence", possible),
            row("0x0000000000000003", "Ledger:func forward", "idempotence", likely),
            row("0x0000000000000004", "Ledger:struct First:func apply", "idempotence", strong),
            row("0x0000000000000005", "Ledger:struct Second:func apply", "idempotence", strong),
            row("0x0000000000000006", "Ledger:func touch", "binary-idempotence", strong),
            row("0x0000000000000007", "Ledger:struct Draft:func persist", "idempotence", strong),
            total,
            unknown,
            row("0x000000000000000A", "Made:func made", "idempotence", strong),
            row("0x000000000000000B", "Ledger:func doubled", "idempotence-lifted", strong),
            row("0x000000000000000C", "Ledger:func refreshed", "mutator-idempotence", strong),
            row("0x000000000000000D", "Ledger:func stage", "round-trip", strong),
            blocked,
            row("0x0000000000000012", "Shapes:func subtracting", "commutativity", lowest),
            shifted
        ]
    }

    /// A row of `template` scoring `score`, with the tier of its band, on
    /// the declaration at `place`: `<file>:<text>`, or
    /// `<file>:<marker>:<text>` for the first line holding `text` after
    /// one holding `marker`, in `Ledger`, `Shapes` or `Made`.
    static func row(_ identity: String, _ place: String, _ template: String, _ score: Int) -> PropertyHarness.Row {
        let parts = place.components(separatedBy: ":")
        let sources = ["Ledger": ledger, "Shapes": shapes, "Made": generated]
        let source = sources[parts.first ?? ""] ?? ""
        let marker = parts.dropFirst().dropLast().first ?? ""
        let line = SignalHarness.line(of: parts.last ?? "", after: marker, in: source)
        return PropertyHarness.Row(
            identity: identity,
            location: "@ROOT@/Sources/Core/\(parts.first ?? "").swift:\(line)",
            template: template,
            score: score,
            tier: PropertyCandidate.ScoreBand(score: score).rawValue
        )
    }

    /// The package scanned with these suggestions, stored and read back.
    static func snapshot() throws -> StoredSnapshot {
        try SignalHarness.stored(files, targets: targets, indexes: ["Core": PropertyHarness.index(rows)])
    }
}
