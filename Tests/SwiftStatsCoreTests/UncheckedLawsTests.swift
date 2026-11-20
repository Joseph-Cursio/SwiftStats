//
//  UncheckedLawsTests.swift
//  SwiftStatsCoreTests
//
//  Unchecked laws (PRD §8): types with a hand-written witness for a kit
//  conformance that no test checks, scored by how many; synthesised,
//  generated and test-only pairs left out; the action for a package with
//  and without the kit.
//

import Foundation
@testable import SwiftStatsCore
import Testing

@Suite("Unchecked laws")
struct UncheckedLawsTests {
    /// Types with custom, synthesised and checked conformances.
    private static let types = """
    struct Money: Equatable {
        let cents: Int

        static func == (lhs: Money, rhs: Money) -> Bool {
            lhs.cents == rhs.cents
        }
    }

    struct Pair: Equatable, Comparable {
        let first: Int

        static func == (lhs: Pair, rhs: Pair) -> Bool {
            lhs.first == rhs.first
        }

        static func < (lhs: Pair, rhs: Pair) -> Bool {
            lhs.first < rhs.first
        }
    }

    struct Plain: Hashable {
        let value: Int
    }

    enum Suit: String {
        case hearts
    }

    enum Code: String {
        case one

        init?(rawValue: String) {
            self = .one
        }
    }

    final class Node: Equatable {
        static func == (lhs: Node, rhs: Node) -> Bool {
            lhs === rhs
        }
    }

    struct Checked: Equatable {
        let value: Int

        static func == (lhs: Checked, rhs: Checked) -> Bool {
            lhs.value == rhs.value
        }
    }
    """

    /// A test checking `Checked`, and a test-only conformance of `Plain`.
    private static let tests = """
    import PropertyLawKit
    import Testing
    @testable import Core

    extension Plain: Comparable {
        static func < (lhs: Plain, rhs: Plain) -> Bool {
            lhs.value < rhs.value
        }
    }

    @Test func checkedLaws() async throws {
        try await checkEquatablePropertyLaws(for: Checked.self)
    }
    """

    /// A generated type with a hand-written witness.
    private static let generated = """
    // DO NOT EDIT
    struct Made: Equatable {
        static func == (lhs: Made, rhs: Made) -> Bool {
            true
        }
    }
    """

    /// A `Package.resolved` pinning SwiftPropertyLaws.
    private static let resolved = """
    {
      "pins" : [
        {
          "identity" : "swiftpropertylaws",
          "kind" : "remoteSourceControl",
          "location" : "https://github.com/Joseph-Cursio/SwiftPropertyLaws.git",
          "state" : { "revision" : "a5ecdab", "version" : "4.11.0" }
        }
      ],
      "version" : 3
    }
    """

    /// The package, depending on the kit when `kit` is true, scanned with
    /// no tools and stored.
    private static func snapshot(kit: Bool) throws -> StoredSnapshot {
        var files = [
            "Sources/Core/Types.swift": types,
            "Sources/Core/Made.swift": generated,
            "Tests/CoreTests/LawTests.swift": tests
        ]
        if kit {
            files["Package.resolved"] = resolved
        }
        let targets = [
            PropertyHarness.target("Core", "library", "Sources/Core", ["Made.swift", "Types.swift"]),
            PropertyHarness.target("CoreTests", "test", "Tests/CoreTests", ["LawTests.swift"])
        ]
        return try SignalHarness.stored(files, targets: targets, tools: SnapshotHarness.noTools)
    }

    @Test("types with hand-written witnesses no test checks are listed by how many, with the protocols")
    func listed() throws {
        let snapshot = try Self.snapshot(kit: false)
        let signal = try SignalHarness.signal(.uncheckedLaws, of: snapshot)

        #expect(signal.leftOut == nil)
        #expect(signal.items.map(\.subject) == ["Core::Pair", "Core::Code", "Core::Money", "Core::Node"])
        #expect(signal.items.map(\.score) == [2, 1, 1, 1])
        #expect(signal.items.map(\.laws?.protocols) == [
            ["Comparable", "Equatable"], ["RawRepresentable"], ["Equatable"], ["Equatable"]
        ])
        #expect(signal.items.map(\.laws?.kitDependency) == [false, false, false, false])
        #expect(signal.members.count == 4)
        #expect(signal.items.first?.file == "Sources/Core/Types.swift")
        #expect(signal.items.first?.line == 9)
    }

    @Test("synthesised, generated, test-only and checked pairs are left out, and the rule counts the synthesised")
    func leftOutPairs() throws {
        let snapshot = try Self.snapshot(kit: false)
        let signal = try SignalHarness.signal(.uncheckedLaws, of: snapshot)
        let made = snapshot.lawChecks.filter { $0.type == "Core::Made" }
        let checked = snapshot.lawChecks.filter { $0.type == "Core::Checked" }

        #expect(made.map(\.generated) == [true])
        #expect(checked.map(\.state) == [.run])
        #expect(snapshot.lawChecks.contains { $0.type == "Core::Plain" && $0.protocolName == "Comparable" } == false)
        // Money, Pair, Plain, Suit, Code, Node and Checked; Made's only pair is generated.
        #expect(signal.candidates == 7)
        // Plain's Hashable and Suit's RawRepresentable.
        #expect(signal.rule == UncheckedLaws.rule + "; 2 unchecked pairs with synthesised witnesses are left out: "
            + "lawful by construction, though not guaranteed (floating-point members, members with their own ==)")
    }

    @Test("the action is to call the kit's checks with the kit, else to add it")
    func action() throws {
        let without = try SignalHarness.signal(.uncheckedLaws, of: try Self.snapshot(kit: false))
        let with = try SignalHarness.signal(.uncheckedLaws, of: try Self.snapshot(kit: true))

        #expect(SignalHarness.rows(without).prefix(3) == [
            "| # | Type | Score | Protocols | Action | Member |",
            "| --- | --- | --- | --- | --- | --- |",
            "| 1 | `Pair` (Sources/Core/Types.swift:9) | 2 | Comparable, Equatable "
                + "| add the SwiftPropertyLaws dependency | yes |"
        ])
        #expect(with.items.map(\.laws?.kitDependency) == [true, true, true, true])
        #expect(SignalHarness.rows(with)[2] == "| 1 | `Pair` (Sources/Core/Types.swift:9) | 2 | Comparable, Equatable "
            + "| add `check<P>PropertyLaws` calls | yes |")
    }

    @Test("a snapshot stored before M4 leaves the signal out")
    func predatesM4() throws {
        let directory = try SnapshotHarness.temporaryDirectory("Signals")
        defer { try? FileManager.default.removeItem(at: directory) }
        let url = directory.appendingPathComponent("stats.sqlite")
        let store = try SnapshotStore(at: url)
        let id = try SnapshotHarness.stored(["Sources/Lib/Lib.swift": Self.types], commit: "c1", in: store).id
        try SnapshotHarness.sqlite(url, "DELETE FROM scanFacts")
        let signal = try SignalHarness.signal(.uncheckedLaws, of: try store.load(id: id))

        #expect(signal.leftOut == "the snapshot predates M4")
        #expect(signal.rule == UncheckedLaws.rule)
    }
}
