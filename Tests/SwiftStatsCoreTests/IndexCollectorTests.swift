import Foundation
@testable import SwiftStatsCore
import Testing

/// The T1 group's place in a scan (M7, design §1): every scan lists the
/// `build`, `index` and `periphery` statuses, they run only when the scan
/// asks for them (`scan --index`), a requested group is skipped for each
/// collector's own settings, the index and outskirts are skipped when the
/// build is, `--drop-index` drops nothing yet, and the index and the dead
/// code compare only when the build does. `IndexGroupTests` runs the
/// build.
@Suite("Index collectors")
struct IndexCollectorTests {
    private static let files = ["Sources/Lib/Lib.swift": "public func one() -> Int { 1 }\n"]
    /// The T1 group's collectors, in the order a scan lists them.
    private static let names = ["build", "index", "periphery"]

    /// The T1 group's statuses, by name, of `files` (with `Self.files`)
    /// scanned with no tools on PATH, the tools skipped for
    /// `toolSkipReason` when given, asking for the group when `index`.
    private static func statuses(
        _ files: [String: String],
        toolSkipReason: String?,
        index: Bool
    ) throws -> [String: CollectorStatus] {
        let package = try TemporaryPackage(Self.files.merging(files) { $1 })
        defer { package.remove() }
        let scanner = PackageScanner(
            describer: package.describer,
            tools: SnapshotHarness.noTools,
            toolSkipReason: toolSkipReason
        )
        let collectors = try scanner.scan(packageAt: package.root, tiers: RequestedTiers(index: index)).collectors
        return Dictionary(uniqueKeysWithValues: collectors.filter { names.contains($0.name) }.map { ($0.name, $0) })
    }

    /// A workspace on a package holding `Self.files` and `files`, storing
    /// in the package's default store.
    private static func workspace(_ files: [String: String]) throws -> (TemporaryPackage, SnapshotWorkspace) {
        let package = try TemporaryPackage(Self.files.merging(files) { $1 })
        let workspace = try SnapshotWorkspace(
            packageRoot: package.root,
            configurationFile: nil,
            storeOverride: nil,
            build: SnapshotHarness.build,
            describer: package.describer,
            tools: SnapshotHarness.noTools
        )
        return (package, workspace)
    }

    /// A snapshot's record of a run of `name`: `ran` with `identity`.
    private static func run(_ name: String, identity: String) -> CollectorRunInfo {
        CollectorRunInfo(
            name: name,
            state: .ran,
            reason: nil,
            version: "1.0",
            identity: identity,
            identityLabel: nil,
            options: ["map: rule"],
            durationMilliseconds: 1
        )
    }

    /// A snapshot whose SwiftStats build is `swiftstats`, whose T1 build is
    /// identified by `build`, and whose index and outskirts runs by
    /// `reader` and `outskirts`.
    private static func info(swiftstats: String, build: String, reader: String, outskirts: String) -> SnapshotInfo {
        SnapshotInfo(
            package: "Probe",
            git: SnapshotHarness.git(commit: "c1"),
            date: "2027-01-15T08:00:00Z",
            toolchain: SnapshotHarness.toolchain,
            collectors: [
                run(BuildAdapter.name, identity: build), run(IndexAdapter.name, identity: reader),
                run(PeripheryAdapter.name, identity: outskirts), run(SwiftStatsCollector.name, identity: swiftstats)
            ]
        )
    }

    @Test("a scan that doesn't ask for the index lists build, index and periphery skipped, saying how to run them")
    func notRequested() throws {
        let plain = try Self.statuses([:], toolSkipReason: nil, index: false)
        let backfill = try Self.statuses([:], toolSkipReason: "backfill runs SwiftStats only", index: false)
        let disabled = try Self.statuses(
            [".swiftstats.yml": "collectors:\n  build:\n    enabled: false\n  periphery:\n    enabled: false\n"],
            toolSkipReason: nil,
            index: false
        )

        let expected = Dictionary(uniqueKeysWithValues: Self.names.map { name in
            (
                name,
                CollectorStatus(
                    name: name,
                    state: .skipped,
                    version: nil,
                    reason: "not requested; scan --index runs it",
                    options: []
                )
            )
        })
        #expect(plain == expected)
        #expect(backfill == expected)
        #expect(disabled == expected)
    }

    @Test("""
        asked for, each collector is skipped for its own settings first: disabled, no swift for the build, \
        no outskirts or a path that isn't executable for periphery, and the tools' skip reason; the index then \
        needs the build
        """)
    func requestedSkips() throws {
        let disabled = try Self.statuses(
            [
                ".swiftstats.yml":
                    "collectors:\n  build:\n    enabled: false\n  index:\n    enabled: false\n"
                    + "  periphery:\n    enabled: false\n"
            ],
            toolSkipReason: nil,
            index: true
        )
        let missing = try Self.statuses([:], toolSkipReason: nil, index: true)
        let badPaths = try Self.statuses(
            [
                ".swiftstats.yml":
                    "collectors:\n  coverage:\n    path: tools/swift\n  periphery:\n    path: tools/outskirts\n"
            ],
            toolSkipReason: nil,
            index: true
        )
        let toolsSkipped = try Self.statuses([:], toolSkipReason: "backfill runs SwiftStats only", index: true)

        #expect(disabled.mapValues(\.reason) == [
            "build": "disabled by collectors.build.enabled",
            "index": "disabled by collectors.index.enabled",
            "periphery": "disabled by collectors.periphery.enabled"
        ])
        #expect(missing.mapValues(\.reason) == [
            "build": "`swift` not found on PATH; set collectors.coverage.path",
            "index": "needs the build: skipped, `swift` not found on PATH; set collectors.coverage.path",
            "periphery": "`outskirts` not found on PATH; set collectors.periphery.path"
        ])
        #expect(badPaths["build"]?.reason == "collectors.coverage.path tools/swift is not an executable file")
        #expect(badPaths["periphery"]?.reason == "collectors.periphery.path tools/outskirts is not an executable file")
        #expect(toolsSkipped.mapValues(\.reason) == Dictionary(uniqueKeysWithValues: Self.names.map { name in
            (name, "backfill runs SwiftStats only")
        }))
        let all = [disabled, missing, badPaths, toolsSkipped].flatMap(\.values)
        #expect(all.allSatisfy { $0.state == .skipped && $0.options.isEmpty })
    }

    @Test("""
        scanWorkingTree passes --index to the scan and stores the statuses without build identities, and a \
        plain rescan lists the group as not requested
        """)
    func workspaceThreading() throws {
        let (package, workspace) = try Self.workspace([:])
        defer { package.remove() }

        let asked = try workspace.scanWorkingTree(history: .skipped("test"), tiers: RequestedTiers(index: true))
        let stored = try workspace.store.info(id: asked.id).collectors.filter { Self.names.contains($0.name) }
        let plain = try workspace.scanWorkingTree(history: .skipped("test"))

        let askedRuns = asked.snapshot.info.collectors.filter { Self.names.contains($0.name) }
        let plainRuns = plain.snapshot.info.collectors.filter { Self.names.contains($0.name) }
        #expect(askedRuns.map(\.name) == Self.names)
        #expect(askedRuns.map(\.reason) == [
            "`swift` not found on PATH; set collectors.coverage.path",
            "needs the build: skipped, `swift` not found on PATH; set collectors.coverage.path",
            "`outskirts` not found on PATH; set collectors.periphery.path"
        ])
        #expect(stored == askedRuns)
        #expect(plainRuns.map(\.reason) == Array(repeating: "not requested; scan --index runs it", count: 3))
        #expect((askedRuns + plainRuns).allSatisfy { $0.identity == nil })
    }

    @Test("--drop-index is accepted but lets nothing go yet: held coverage too damaged to read still stops the rescan")
    func dropIndexDropsNothing() throws {
        let (package, workspace) = try CarrySamples.store()
        defer { package.remove() }
        let covered = try CarrySamples.covered(try CarrySamples.scan(git: CarrySamples.clean))
        let held = try workspace.save(covered, drop: [])
        try SnapshotHarness.sqlite(
            workspace.store.url,
            "UPDATE coverageLine SET lines = '1:5' WHERE snapshotId = \(held.id) AND file = 'Sources/Kit/Kit.swift'"
        )
        let rescan = try CarrySamples.scan(git: CarrySamples.clean, date: SnapshotHarness.date + CarrySamples.day)

        #expect(throws: StoreError.self) {
            try workspace.save(rescan, drop: [.index, .mutation])
        }
        #expect(try workspace.store.snapshotID(package: "Probe", packagePath: "", commit: "c1", isDirty: false)
            == held.id)
        let dropped = try workspace.save(rescan, drop: [.coverage, .index])

        #expect(try workspace.store.load(id: dropped.id).coverage == nil)
    }

    @Test("""
        build, index and periphery compare only when SwiftStats' own build does, and the index and the dead \
        code only when the T1 build does too
        """)
    func comparability() {
        let older = Self.info(swiftstats: "inputs:aaa", build: "swift:6.4.2", reader: "git:64aa", outskirts: "sha256:a")
        let otherSwiftStats = Self.info(
            swiftstats: "inputs:bbb",
            build: "swift:6.4.2",
            reader: "git:64aa",
            outskirts: "sha256:a"
        )
        let otherToolchain = Self.info(
            swiftstats: "inputs:aaa",
            build: "swift:6.4.1",
            reader: "git:64aa",
            outskirts: "sha256:a"
        )
        let otherOutskirts = Self.info(
            swiftstats: "inputs:aaa",
            build: "swift:6.4.2",
            reader: "git:64aa",
            outskirts: "sha256:b"
        )
        let outcomes = { (new: SnapshotInfo) in
            Dictionary(uniqueKeysWithValues: Comparability.compare(older, new)
                .filter { Self.names.contains($0.name) }
                .map { ($0.name, $0) })
        }

        #expect(outcomes(older).values.allSatisfy { $0.outcome == .compared })
        #expect(outcomes(otherSwiftStats).mapValues(\.reason) == [
            "build": "SwiftStats' build differs, and its own code maps the timings and warnings",
            "index": "SwiftStats' build differs, and its own code reads the index",
            "periphery": "SwiftStats' build differs, and its own code maps the dead code"
        ])
        let buildDiffers = "the build differs: the index and the dead code come from it"
        #expect(outcomes(otherToolchain).mapValues(\.reason) == [
            "build": "different builds", "index": buildDiffers, "periphery": buildDiffers
        ])
        #expect(outcomes(otherToolchain).values.allSatisfy { $0.outcome == .notComparable })
        #expect(outcomes(otherOutskirts)["build"]?.outcome == .compared)
        #expect(outcomes(otherOutskirts)["index"]?.outcome == .compared)
        #expect(outcomes(otherOutskirts)["periphery"]?.reason == "different builds")
    }
}
