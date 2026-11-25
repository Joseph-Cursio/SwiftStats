import Foundation
@testable import SwiftStatsCore
import Testing

/// `diff`'s comparability and its empty case (PRD §6.6; M2 done-when 1 and 3).
@Suite("Snapshot diff")
struct SnapshotDiffTests {
    /// A small package to diff.
    private static let files = [
        "Sources/Lib/Lib.swift": """
        public func double(_ value: Int) -> Int {
            let result = value * 2
            return result
        }
        """,
        "Tests/LibTests/LibTests.swift": """
        import Testing
        @Test func doubles() { #expect(double(2) == 4) }
        """
    ]

    /// `package` scanned at commit `c1` as `build`, stored in a new store
    /// under `directory`, and read back.
    private static func stored(
        _ package: TemporaryPackage,
        build: SwiftStatsBuild,
        store name: String,
        in directory: URL
    ) throws -> StoredSnapshot {
        let store = try SnapshotStore(at: directory.appendingPathComponent(name))
        let snapshot = try SnapshotHarness.scan(package, commit: "c1", build: build, tools: SnapshotHarness.noTools)
        return try store.load(id: try store.save(snapshot))
    }

    @Test("a snapshot diffed with itself is empty, though every external collector was skipped (done-when 1)")
    func selfDiff() throws {
        let directory = try SnapshotHarness.temporaryDirectory("Diff")
        defer { try? FileManager.default.removeItem(at: directory) }
        let store = try SnapshotStore(at: directory.appendingPathComponent("stats.sqlite"))
        let snapshot = try SnapshotHarness.stored(Self.files, commit: "c1", in: store)

        let diff = SnapshotDiff.diff(snapshot, snapshot)

        #expect(diff.isEmpty)
        #expect(diff.families.isEmpty && diff.functions.isEmpty && diff.rollups.isEmpty)
        let outcomes = Dictionary(uniqueKeysWithValues: diff.collectors.map { ($0.name, $0.outcome) })
        #expect(outcomes == [
            "build": .notCollected, "coverage": .notCollected, "dependencies": .notCollected,
            "history": .notCollected, "index": .notCollected, "periphery": .notCollected,
            "swiftclonedetector": .notCollected, "swifteffectinference": .compared,
            "swiftinferproperties": .notCollected, "swiftlint": .notCollected, "swiftmutator": .notCollected,
            "swiftprojectlint": .notCollected, "swiftstats": .compared
        ])
        #expect(MarkdownDiff.render(diff).contains("No changes."))
    }

    @Test("""
        two snapshots of one commit by different SwiftStats builds compare none of SwiftStats' measurements \
        (done-when 3)
        """)
    func differentBuilds() throws {
        let directory = try SnapshotHarness.temporaryDirectory("Diff")
        defer { try? FileManager.default.removeItem(at: directory) }
        let package = try TemporaryPackage(Self.files)
        defer { package.remove() }
        let older = SwiftStatsBuild(identity: "inputs:aaa", label: "git:1111111")
        let newer = SwiftStatsBuild(identity: "inputs:bbb", label: "git:2222222")

        // One store keeps one clean snapshot per commit, so each build
        // writes to its own store.
        let first = try Self.stored(package, build: older, store: "a.sqlite", in: directory)
        let second = try Self.stored(package, build: newer, store: "b.sqlite", in: directory)
        let diff = SnapshotDiff.diff(first, second)

        #expect(first.info.git.commit == second.info.git.commit)
        let own = diff.collectors.first { $0.name == SwiftStatsCollector.name }
        #expect(own?.outcome == .notComparable)
        #expect(own?.reason == "different builds")
        #expect(diff.families.isEmpty && diff.functions.isEmpty)
        #expect(diff.rollups.isEmpty)
        #expect(diff.isEmpty == false)
        #expect(MarkdownDiff.render(diff).contains("| swiftstats | not-comparable | different builds |"))
    }

    @Test("side effects compare only when SwiftStats' build does, since SwiftStats' own code maps them")
    func sideEffectsNeedOwnBuild() throws {
        let directory = try SnapshotHarness.temporaryDirectory("Diff")
        defer { try? FileManager.default.removeItem(at: directory) }
        let package = try TemporaryPackage(Self.files)
        defer { package.remove() }
        let older = SwiftStatsBuild(identity: "inputs:aaa", label: nil)
        let newer = SwiftStatsBuild(identity: "inputs:bbb", label: nil)

        let first = try Self.stored(package, build: older, store: "a.sqlite", in: directory)
        let second = try Self.stored(package, build: newer, store: "b.sqlite", in: directory)
        let effects = SnapshotDiff.diff(first, second).collectors.first { $0.name == EffectCollector.name }
        let same = SnapshotDiff.diff(first, first).collectors.first { $0.name == EffectCollector.name }

        let runs = [first, second].compactMap { snapshot in
            snapshot.info.collectors.first { $0.name == EffectCollector.name }
        }
        #expect(runs.map(\.identity) == [EffectInferenceRevision.identity, EffectInferenceRevision.identity])
        #expect(runs.map(\.version) == [EffectInferenceRevision.pinned, EffectInferenceRevision.pinned])
        #expect(runs[0].options == runs[1].options)
        #expect(effects?.outcome == .notComparable)
        #expect(effects?.reason == "SwiftStats' build differs, and its own code maps the side effects")
        #expect(same?.outcome == .compared)
        #expect(second.rollups.contains { $0.collector == EffectCollector.name })
    }

    @Test("when SwiftStats' builds differ, changed code gives no function or roll-up deltas, and the Markdown says why")
    func differentBuildsWithheld() throws {
        let directory = try SnapshotHarness.temporaryDirectory("Diff")
        defer { try? FileManager.default.removeItem(at: directory) }
        let before = try TemporaryPackage(Self.files)
        defer { before.remove() }
        let extra = "public func triple(_ value: Int) -> Int {\n    let result = value * 3\n    return result\n}\n"
        let after = try TemporaryPackage(Self.files.merging(["Sources/Lib/More.swift": extra]) { $1 })
        defer { after.remove() }

        let first = try Self.stored(before, build: SnapshotHarness.build, store: "a.sqlite", in: directory)
        let second = try Self.stored(
            after,
            build: SwiftStatsBuild(identity: "inputs:other", label: nil),
            store: "b.sqlite",
            in: directory
        )
        let diff = SnapshotDiff.diff(first, second)

        #expect(first.functions.count + 1 == second.functions.count)
        #expect(diff.families.isEmpty && diff.functions.isEmpty && diff.rollups.isEmpty)
        let text = MarkdownDiff.render(diff)
        #expect(text.contains("Functions and roll-ups: not compared"))
        #expect(text.contains("No function changes") == false)
    }

    @Test("a law state or side-effect count missing from one snapshot is zero, so a fall to zero is judged")
    func countsFallToZero() throws {
        let directory = try SnapshotHarness.temporaryDirectory("Diff")
        defer { try? FileManager.default.removeItem(at: directory) }
        let source = ["Sources/Lib/Lib.swift": "public struct Amount: Equatable {\n    let value: Int\n}\n"]
        let unchecked = try TemporaryPackage(source.merging([
            "Tests/LibTests/LibTests.swift": "import Testing\n@Test func amounts() {}\n"
        ]) { $1 })
        defer { unchecked.remove() }
        let checked = try TemporaryPackage(source.merging([
            "Tests/LibTests/LibTests.swift": """
            import Testing
            @Test func amounts() async throws {
                try await checkEquatablePropertyLaws(for: Amount.self, using: Amount.gen())
            }
            """
        ]) { $1 })
        defer { checked.remove() }

        let first = try Self.stored(unchecked, build: SnapshotHarness.build, store: "a.sqlite", in: directory)
        let second = try Self.stored(checked, build: SnapshotHarness.build, store: "b.sqlite", in: directory)
        let laws = SnapshotDiff.diff(first, second).rollups.filter { $0.delta.metric.hasPrefix("laws.") }

        // `laws.state` has no `notRun` key once nothing is unchecked, and
        // no `run` key before anything is checked.
        #expect(laws.map { "\($0.name) \($0.delta.metric) \($0.delta.before ?? -1) \($0.delta.after ?? -1)" } == [
            "Lib laws.state.notRun 1.0 0.0", "Lib laws.state.run 0.0 1.0",
            "production laws.state.notRun 1.0 0.0", "production laws.state.run 0.0 1.0"
        ])
        #expect(laws.map(\.delta.verdict) == [.better, .neutral, .better, .neutral])
        #expect(CountedMetrics.value(nil, metric: "effects.tier.idempotent") == 0)
        #expect(CountedMetrics.value(nil, metric: "effects.purity.pure") == 0)
        #expect(CountedMetrics.value(nil, metric: "cognitive.p90") == nil)
    }

    @Test("a change to excluded or generated globs makes SwiftStats' measurements not comparable")
    func differentOptions() throws {
        let directory = try SnapshotHarness.temporaryDirectory("Diff")
        defer { try? FileManager.default.removeItem(at: directory) }
        let plain = try TemporaryPackage(Self.files)
        defer { plain.remove() }
        let configuration = [".swiftstats.yml": "excluded:\n  - Tests/**\n"]
        let excluding = try TemporaryPackage(Self.files.merging(configuration) { $1 })
        defer { excluding.remove() }

        let first = try Self.stored(plain, build: SnapshotHarness.build, store: "a.sqlite", in: directory)
        let second = try Self.stored(excluding, build: SnapshotHarness.build, store: "b.sqlite", in: directory)
        let own = SnapshotDiff.diff(first, second).collectors.first { $0.name == SwiftStatsCollector.name }

        #expect(own?.outcome == .notComparable)
        #expect(own?.reason == "different options")
    }

    @Test("an external tool compares when its binary and options match, and the graph needs SwiftStats to match too")
    func comparability() {
        let run = { (name: String, identity: String?, state: CollectorState) in
            CollectorRunInfo(
                name: name,
                state: state,
                reason: state == .ran ? nil : "not found",
                version: "1",
                identity: identity,
                identityLabel: nil,
                options: [],
                durationMilliseconds: 0
            )
        }
        let info = { (runs: [CollectorRunInfo]) in
            SnapshotInfo(
                package: "P",
                git: .outsideGit,
                date: "d",
                toolchain: SnapshotHarness.toolchain,
                collectors: runs
            )
        }
        let older = info([
            run("swiftstats", "inputs:a", .ran), run("swiftlint", "sha256:x", .ran),
            run("dependencies", "swift:6.4", .ran), run("swiftprojectlint", nil, .skipped)
        ])
        let newer = info([
            run("swiftstats", "inputs:b", .ran), run("swiftlint", "sha256:x", .ran),
            run("dependencies", "swift:6.4", .ran), run("swiftprojectlint", "sha256:y", .ran)
        ])

        let outcomes = Comparability.compare(older, newer)

        #expect(outcomes.map(\.name) == ["dependencies", "swiftlint", "swiftprojectlint", "swiftstats"])
        #expect(outcomes.map(\.outcome) == [.notComparable, .compared, .notCollected, .notComparable])
        #expect(outcomes[2].reason == "skipped in the older snapshot: not found")
    }
}
