//
//  USRMatchingTests.swift
//  SwiftStatsCoreTests
//
//  The `usr` match rule and the `usr changed` facts (M7, design §10.3) on
//  hand-made USRs: families whose roots share a primary USR held once on
//  each side, of one kind, match by `usr` after the key rules and before
//  the body hash, their nested records following; anything less certain
//  doesn't; and a record keeping its key but not its USR is a fact under
//  its family. The compiler's own USRs are checked in `IndexDiffTests`.
//

import Foundation
@testable import SwiftStatsCore
import Testing

@Suite("USR match rule")
struct USRMatchingTests {
    /// The older files for the rule-order tests: a function kept as it is, a
    /// private one moved later, and one renamed later.
    private static let orderedOld = [
        "Sources/Lib/A.swift": """
        func same() -> Int {
            1
        }

        private func helper() -> Int {
            2
        }

        func before() -> Int {
            let value = 3
            return value
        }
        """
    ]
    /// The newer files for the rule-order tests.
    private static let orderedNew = [
        "Sources/Lib/A.swift": """
        func same() -> Int {
            1
        }

        func after() -> Int {
            let value = 3
            return value
        }
        """,
        "Sources/Lib/B.swift": """
        private func helper() -> Int {
            2
        }
        """
    ]
    /// The rule-order files' USRs: the renamed function's changes with its key.
    private static let orderedUSRs = IndexFacts(
        old: [
            "Lib::func same() -> Int": "s:same",
            "Lib::func helper() -> Int @ Sources/Lib/A.swift": "s:helper",
            "Lib::func before() -> Int": "s:before"
        ],
        new: [
            "Lib::func same() -> Int": "s:same",
            "Lib::func helper() -> Int @ Sources/Lib/B.swift": "s:helper",
            "Lib::func after() -> Int": "s:after"
        ]
    )

    /// Rows for `files` (path → source) of module `Lib`.
    private static func rows(_ files: [String: String]) -> [FunctionRow] {
        files.flatMap { file, source in
            KeyCollisions.resolve(CollectorHarness.collect(source, file: file)).records
                .map { FunctionRow($0, snapshotId: 0) }
        }
    }

    /// The matches of `old` against `new` with `usrs`, as `method new key`
    /// (`removed`/`added` for the rest), sorted.
    private static func outcome(
        _ old: [String: String],
        _ new: [String: String],
        usrs: IndexFacts
    ) -> [String] {
        let result = FamilyMatcher.match(
            old: FunctionFamily.families(rows(old)),
            new: FunctionFamily.families(rows(new)),
            usrs: usrs
        )
        return (result.matches.map { "\($0.method.rawValue) \($0.new.id)" }
            + result.removed.map { "removed \($0.id)" }
            + result.added.map { "added \($0.id)" }).sorted()
    }

    @Test("""
        roots sharing a primary USR held once on each side, of one kind, match by usr, a certain match, though \
        their keys differ, and their nested records pair as in any match
        """)
    func matched() throws {
        let old = [
            "Sources/Lib/A.swift": """
            func total(of values: [Int]) -> Int {
                func step() -> Int { 1 }
                return values.reduce(0, +) + step()
            }
            """
        ]
        let new = [
            "Sources/Lib/A.swift": """
            func total(of values: Array<Int>) -> Int {
                func step() -> Int { 1 }
                return values.reduce(0, +) + step()
            }
            """
        ]
        let usrs = IndexFacts(
            old: ["Lib::func total(of: [Int]) -> Int": "s:3Lib5totalF"],
            new: ["Lib::func total(of: Array<Int>) -> Int": "s:3Lib5totalF"]
        )

        let result = FamilyMatcher.match(
            old: FunctionFamily.families(Self.rows(old)),
            new: FunctionFamily.families(Self.rows(new)),
            usrs: usrs
        )

        let match = try #require(result.matches.first)
        #expect(result.matches.count == 1 && result.removed.isEmpty && result.added.isEmpty)
        #expect(match.method == .usr)
        #expect(MatchMethod.usr.uncertainty < MatchMethod.bodyHash.uncertainty)
        let members = MemberPairing.pair(match.old, match.new)
        #expect(members.pairs.count == 2 && members.unmatchedOld.isEmpty && members.unmatchedNew.isEmpty)
        let change = try #require(SnapshotDiff.change(match, members: members, usrs: usrs))
        #expect(change.statuses == [.renamed])
        #expect(change.matchedBy == .usr)
        #expect(change.usrChanges.isEmpty)
    }

    @Test("""
        the key rules come first and the body hash after: a same key matches by key and a moved private function \
        by its file-scoped key, USRs or not; a renamed body whose USR changed still matches by body hash
        """)
    func order() {
        #expect(Self.outcome(Self.orderedOld, Self.orderedNew, usrs: Self.orderedUSRs) == [
            "body-hash Lib::func after() -> Int",
            "file-scoped-key Lib::func helper() -> Int @ Sources/Lib/B.swift",
            "key Lib::func same() -> Int"
        ])
    }

    @Test("a renamed record whose USR changes with its key is no usr changed fact: only a kept key is")
    func renamedIsNoUSRChange() throws {
        let result = FamilyMatcher.match(
            old: FunctionFamily.families(Self.rows(Self.orderedOld)),
            new: FunctionFamily.families(Self.rows(Self.orderedNew)),
            usrs: Self.orderedUSRs
        )
        let renamed = try #require(result.matches.first { $0.method == .bodyHash })

        let change = try #require(
            SnapshotDiff.change(renamed, members: MemberPairing.pair(renamed.old, renamed.new), usrs: Self.orderedUSRs)
        )

        #expect(change.statuses == [.renamed] && change.usrChanges.isEmpty)
    }

    @Test("""
        nothing matches by usr when the roots' kinds differ, a USR is on two unmatched roots of a side, only one \
        side has the USR, the families have no root (a computed property's accessors), or there are no USRs
        """)
    func unmatched() throws {
        let old = [
            "Sources/Lib/A.swift": """
            struct Box {
                func make() -> Int { 1 }
            }

            func first() -> Int { 1 }
            func second() -> Int { 2 }
            func lonely() -> Int { 3 }
            var total: Int { 4 }
            """
        ]
        let new = [
            "Sources/Lib/A.swift": """
            struct Box {
                init() {}
            }

            func third() -> Int { 1 }
            func alone() -> Int { 3 }
            var sum: Int { 4 }
            """
        ]
        let oldAccessor = try #require(Self.rows(old).first { $0.kind == .accessor }).key
        let newAccessor = try #require(Self.rows(new).first { $0.kind == .accessor }).key
        let usrs = IndexFacts(
            old: [
                "Lib::Box::func make() -> Int": "s:box",
                "Lib::func first() -> Int": "s:shared",
                "Lib::func second() -> Int": "s:shared",
                "Lib::func lonely() -> Int": "s:lonely",
                oldAccessor: "s:property"
            ],
            new: [
                "Lib::Box::init()": "s:box",
                "Lib::func third() -> Int": "s:shared",
                newAccessor: "s:property"
            ]
        )
        let expected = [
            "added Lib::Box::init()", "added Lib::func alone() -> Int", "added Lib::func third() -> Int",
            "added Lib::var sum: Int", "removed Lib::Box::func make() -> Int", "removed Lib::func first() -> Int",
            "removed Lib::func lonely() -> Int", "removed Lib::func second() -> Int", "removed Lib::var total: Int"
        ]

        #expect(Self.outcome(old, new, usrs: usrs) == expected)
        #expect(Self.outcome(old, new, usrs: .empty) == expected)
    }

    @Test("""
        a matched record that keeps its key but whose USR differs on both sides is a usr changed fact under its \
        family; a USR on one side only, or the same USR, is none
        """)
    func changes() throws {
        let source = [
            "Sources/Lib/A.swift": """
            func scaled(_ value: Length) -> Length {
                func half() -> Length { value / 2 }
                return half() + value
            }

            func plain() -> Int { 1 }
            """
        ]
        let parent = "Lib::func scaled(_: Length) -> Length"
        let nested = parent + " / func half() -> Length"
        let usrs = IndexFacts(
            old: [parent: "s:scaledInt", nested: "s:halfInt", "Lib::func plain() -> Int": "s:plain"],
            new: [parent: "s:scaledDouble", nested: "s:halfDouble"]
        )
        let result = FamilyMatcher.match(
            old: FunctionFamily.families(Self.rows(source)),
            new: FunctionFamily.families(Self.rows(source)),
            usrs: usrs
        )

        let changes = result.matches.compactMap { match in
            SnapshotDiff.change(match, members: MemberPairing.pair(match.old, match.new), usrs: usrs)
        }

        #expect(result.matches.allSatisfy { $0.method == .key })
        #expect(changes.count == 1)
        let change = try #require(changes.first)
        #expect(change.key == parent && change.statuses == [.usrChanged] && change.changedRecords.isEmpty)
        #expect(change.usrChanges == [
            USRChange(key: parent, before: "s:scaledInt", after: "s:scaledDouble"),
            USRChange(key: nested, before: "s:halfInt", after: "s:halfDouble")
        ])
        #expect(IndexFacts(old: [parent: "s:same"], new: [parent: "s:same"]).changes(
            Self.rows(source).map { ($0, $0) }
        ).isEmpty)
    }
}
