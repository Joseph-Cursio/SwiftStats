import Foundation
@testable import SwiftStatsCore
import Testing

/// How `diff` groups records into families and matches them (PRD §6.6).
@Suite("Family matching")
struct FamilyMatchingTests {
    /// Rows for `files` (path → source) of module `Lib`.
    private static func rows(_ files: [String: String]) -> [FunctionRow] {
        files.flatMap { file, source in
            KeyCollisions.resolve(CollectorHarness.collect(source, file: file)).records
                .map { FunctionRow($0, snapshotId: 0) }
        }
    }

    /// The family changes from `old` to `new`, as `diff` reports them.
    private static func changes(_ old: [String: String], _ new: [String: String]) -> [FamilyChange] {
        let result = FamilyMatcher.match(
            old: FunctionFamily.families(rows(old)),
            new: FunctionFamily.families(rows(new))
        )
        let matched = result.matches.compactMap { match in
            SnapshotDiff.change(match, members: MemberPairing.pair(match.old, match.new))
        }
        return matched + result.removed.map { SnapshotDiff.unmatched($0, status: .removed) }
            + result.added.map { SnapshotDiff.unmatched($0, status: .added) }
    }

    @Test("a private function moved to another file and edited is matched by key, children and all")
    func privateMoveAndEdit() {
        let old = [
            "Sources/Lib/A.swift": """
            private func helper() -> Int {
                func step() -> Int { 1 }
                return step()
            }
            """
        ]
        let new = [
            "Sources/Lib/B.swift": """
            private func helper() -> Int {
                func step() -> Int { 1 }
                return step() + 1
            }
            """
        ]

        let changes = Self.changes(old, new)

        #expect(changes.count == 1)
        #expect(changes[0].matchedBy == .fileScopedKey)
        #expect(changes[0].oldFile == "Sources/Lib/A.swift" && changes[0].newFile == "Sources/Lib/B.swift")
        #expect(changes[0].statuses == [.changed, .moved])
        #expect(changes[0].changedRecords == ["Lib::func helper() -> Int @ Sources/Lib/B.swift"], "\(changes)")
        #expect(changes[0].records.count == 2)
    }

    @Test("a function that stops being private in the same file is matched, as an access change")
    func accessChange() {
        let old = [
            "Sources/Lib/A.swift": "private func helper() -> Int {\n    1\n}\n"
        ]
        let new = [
            "Sources/Lib/A.swift": "func helper() -> Int {\n    1\n}\n"
        ]

        let changes = Self.changes(old, new)

        #expect(changes.count == 1)
        #expect(changes[0].statuses == [.accessChanged])
        #expect(changes[0].key == "Lib::func helper() -> Int")
        #expect(changes[0].matchedBy == .fileScopedKey)
    }

    @Test("a renamed function with a multi-line body is matched by body hash; one-line bodies are not")
    func renameByBody() {
        let old = [
            "Sources/Lib/A.swift": """
            func total() -> Int {
                let sum = 1 + 2
                return sum
            }
            func yes() -> Bool { true }
            """
        ]
        let new = [
            "Sources/Lib/A.swift": """
            func sum() -> Int {
                let sum = 1 + 2
                return sum
            }
            func ok() -> Bool { true }
            """
        ]

        let changes = Self.changes(old, new)

        let renamed = changes.first { $0.matchedBy == .bodyHash }
        #expect(renamed?.oldKey == "Lib::func total() -> Int")
        #expect(renamed?.key == "Lib::func sum() -> Int")
        #expect(changes.filter { $0.statuses == [.removed] }.map(\.key) == ["Lib::func yes() -> Bool"])
        #expect(changes.filter { $0.statuses == [.added] }.map(\.key) == ["Lib::func ok() -> Bool"])
    }

    @Test("a one-line body laid out over three lines is no evidence of a rename either")
    func laidOutOneLineBody() {
        let old = ["Sources/Lib/A.swift": "func isEnabled() -> Bool {\n    true\n}\n"]
        let new = ["Sources/Lib/A.swift": "func isVisible() -> Bool {\n    true\n}\n"]

        let changes = Self.changes(old, new)

        #expect(changes.map(\.statuses).sorted { $0.description < $1.description } == [[.added], [.removed]])
        #expect(changes.allSatisfy { $0.matchedBy == nil })
    }

    @Test("two private functions of one name, both files renamed, are not paired by guesswork")
    func ambiguousPrivateMoves() {
        let old = [
            "Sources/Lib/A.swift": "private func helper() -> String {\n    \"a\"\n}\n",
            "Sources/Lib/B.swift": "private func helper() -> String {\n    \"b\"\n}\n"
        ]
        let new = [
            "Sources/Lib/Z.swift": "private func helper() -> String {\n    \"z\"\n}\n",
            "Sources/Lib/C.swift": "private func helper() -> String {\n    \"c\"\n}\n"
        ]

        let changes = Self.changes(old, new)

        #expect(changes.count == 4)
        #expect(changes.allSatisfy { $0.matchedBy == nil })
    }

    @Test("nested functions in a computed property pair by key, not by position")
    func propertyNestedFunctions() {
        let property = { (first: String, second: String) in
            "struct Box {\n    var total: Int {\n\(first)\n\(second)\n        return small() + large(1, 2)\n    }\n}\n"
        }
        let small = "        func small() -> Int { 1 }"
        let large = """
                    func large(_ left: Int, _ right: Int) -> Int {
                        left > right ? left : right
                    }
            """
        let old = ["Sources/Lib/A.swift": property(small, large)]
        let new = ["Sources/Lib/A.swift": property(large, small)]

        let changes = Self.changes(old, new)

        // Only the getter's own tokens moved; each nested function kept its body.
        #expect(changes.count == 1)
        #expect(changes[0].changedRecords == ["Lib::Box::var total: Int { get }"])
    }

    @Test("editing a nested function is one change to its family, naming both records")
    func nestedEdit() {
        let old = [
            "Sources/Lib/A.swift": "func outer() -> Int {\n    func inner() -> Int { 1 }\n    return inner()\n}\n"
        ]
        let new = [
            "Sources/Lib/A.swift": "func outer() -> Int {\n    func inner() -> Int { 2 }\n    return inner()\n}\n"
        ]

        let changes = Self.changes(old, new)

        #expect(changes.count == 1)
        #expect(changes[0].changedRecords == [
            "Lib::func outer() -> Int", "Lib::func outer() -> Int / func inner() -> Int"
        ])
    }

    @Test("a computed property's accessors are one family, and move together")
    func propertyAccessors() {
        let property = """
            struct Box {
                var count = 0
            }
            extension Box {
                var total: Int {
                    get { count }
                    set { count = newValue }
                }
            }
            """
        let families = FunctionFamily.families(Self.rows(["Sources/Lib/A.swift": property]))

        let changes = Self.changes(["Sources/Lib/A.swift": property], ["Sources/Lib/B.swift": property])

        #expect(families.map(\.id) == ["Lib::Box::var total: Int"])
        #expect(families[0].members.count == 2)
        #expect(changes.count == 1)
        #expect(changes[0].newFile == "Sources/Lib/B.swift")
        #expect(changes[0].changedRecords.isEmpty)
    }

    @Test("removing the first of two same-named local functions pairs the survivor with its own body")
    func siblingRenumbering() {
        let old = [
            "Sources/Lib/A.swift": """
            func pick(_ flag: Bool) -> Int {
                if flag {
                    func f() -> Int { 1 }
                    return f()
                }
                func f() -> Int { 2 }
                return f()
            }
            """
        ]
        let new = [
            "Sources/Lib/A.swift": """
            func pick(_ flag: Bool) -> Int {
                func f() -> Int { 2 }
                return f()
            }
            """
        ]

        let changes = Self.changes(old, new)

        // The parent changed and one local function went; the survivor,
        // renumbered from ` #2`, kept its body.
        #expect(changes.count == 1)
        #expect(changes[0].changedRecords.count == 2)
        #expect(changes[0].changedRecords.contains("Lib::func pick(_: Bool) -> Int"))
    }

    @Test("key forms drop file parts with collision locations, and sibling numbers")
    func keyForms() {
        let key = "Lib::func f() @ Sources/A.swift:12:4 / func g() #2"

        #expect(KeyForm.withoutFile(key, file: "Sources/A.swift") == "Lib::func f() / func g() #2")
        #expect(KeyForm.withoutOrdinals(key) == "Lib::func f() @ Sources/A.swift:12:4 / func g()")
        let replaced = KeyForm.replacingFileSegments(in: key, file: "Sources/A.swift", with: " @ B")
        #expect(replaced == "Lib::func f() @ B / func g() #2")
        #expect(KeyForm.hasFileSegment(key, file: "Sources/A.swift"))
        #expect(KeyForm.withoutOrdinals("Lib::func a #b") == "Lib::func a #b")
    }

    @Test("each metric has a fixed direction")
    func directions() {
        #expect(MetricDirection.of("cognitive.p90") == .lowerIsBetter)
        #expect(MetricDirection.of("cognitive.count") == .neutral)
        #expect(MetricDirection.of("findings.swiftlint.line_length") == .lowerIsBetter)
        #expect(MetricDirection.of("tests.tests.swiftTesting.unit") == .higherIsBetter)
        #expect(MetricDirection.of("tests.assertionsPerTest.median") == .higherIsBetter)
        #expect(MetricDirection.of("api.documentedPublicDeclarations") == .higherIsBetter)
        #expect(MetricDirection.of("functions.func") == .neutral)
        #expect(MetricDirection.of("strippedLines") == .lowerIsBetter)
        #expect(MetricDelta(metric: "strippedLines", before: 4, after: 6).verdict == .worse)
        #expect(MetricDelta(metric: "documentedFunctions", before: 4, after: 6).verdict == .better)
        #expect(MetricDelta(metric: "files", before: 4, after: 6).verdict == .neutral)
    }

    @Test("roll-up numbers are named by path, attributed to their collector, and skip flags and nulls")
    func rollupMetrics() throws {
        let package = try TemporaryPackage([
            "Sources/Lib/Lib.swift": "func one() -> Int {\n    precondition(true)\n    return 1\n}\n"
        ])
        defer { package.remove() }
        let report = try package.scan(tools: SnapshotHarness.noTools)
        let production = try #require(report.rollups.first { $0.scope == .project && $0.name == "production" })

        let metrics = Dictionary(uniqueKeysWithValues: try RollupMetrics.metrics(of: production).map { ($0.path, $0) })

        #expect(metrics["findings.swiftstats.precondition"]?.value == 1)
        #expect(metrics["functionLength.total"]?.collector == "swiftstats")
        #expect(metrics["tests.lineRatio.deadCodeExcluded"] == nil)
        #expect(metrics["api.overExposed"] == nil)
        #expect(RollupMetrics.collector(of: ["api", "overExposed"]) == "swiftprojectlint")
        #expect(RollupMetrics.collector(of: ["findingKinds", "swiftlint", "defect"]) == "swiftlint")
    }
}
