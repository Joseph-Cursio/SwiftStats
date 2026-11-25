//
//  IndexFixtureScan.swift
//  SwiftStatsCoreTests
//
//  A copy of the Index fixture scanned with `--index` against a fake
//  toolchain acting out its recorded build (M7, design §13 step 5a), the
//  `index` collector reading a recorded dump through `RecordedIndexSource`
//  instead of a store: `@ROOT@` stands for the copy, `@BUILD@` for its
//  `.swiftstats/index-build` and `@DEP@` for an IndexDep beside it. The
//  toolchain holds an empty `libIndexStore.dylib`, which only the locator
//  looks for. A scan can change the build's scenario, the copy before the
//  scan and the recorded source the factory gives. The scan runs on a
//  thread of its own (`ThreadRun`), so a test awaiting it holds no pool
//  thread for its seconds of work. Nothing is built or read for real.
//

import Foundation
@testable import SwiftStatsCore

/// A scan of the Index fixture with its recorded build and index.
struct IndexFixtureScan {
    /// The fake build's scenario: the recorded first build by default.
    var scenario: FakeToolchain.BuildScenario
    /// Further collector keys for `.swiftstats.yml`, indented as under
    /// `collectors:`.
    var extra = ""
    /// The recorded dump the index reads.
    var dump = "reader.json"
    /// Whether the toolchain holds a `libIndexStore.dylib`.
    var hasLibrary = true
    /// What to do to the copy before the scan.
    var prepare: @Sendable (BuildFixture) throws -> Void = { _ in
        // The copy as made.
    }
    /// The source the index reads, made from the recorded dump with the
    /// copy's paths put back.
    var source: @Sendable (RecordedIndexSource) throws -> any IndexStoreSource = \.self

    /// A scan of the recorded build and dump.
    init() throws {
        scenario = try FakeToolchain.recordedBuild()
    }

    /// The paths the recordings' placeholders stand for in `fixture`, as
    /// `RecordedIndexSource` puts them back.
    static func restoring(_ fixture: BuildFixture) -> [String: String] {
        [
            IndexFixture.rootToken: fixture.paths.root,
            IndexFixture.buildToken: fixture.paths.build,
            IndexFixture.dependencyToken: fixture.paths.dependency
        ]
    }

    /// The recorded describe with the stale case's manifest edits:
    /// `Formatting.swift` renamed `LineFormatting.swift` in `IndexCore`,
    /// and `Relay.swift` moved from `index-kit` to `index-support`.
    static func staleDescribe() throws -> String {
        let data = try IndexFixture.data("describe.json")
        guard var object = try JSONSerialization.jsonObject(with: data) as? [String: Any],
              let targets = object["targets"] as? [[String: Any]] else {
            throw IndexFixtureScanError(description: "describe.json isn't an object with targets")
        }
        object["targets"] = targets.map { target -> [String: Any] in
            var edited = target
            let sources = target["sources"] as? [String] ?? []
            switch target["name"] as? String {
            case "IndexCore":
                edited["sources"] = sources.map { $0 == "Formatting.swift" ? "LineFormatting.swift" : $0 }

            case "index-kit":
                edited["sources"] = sources.filter { $0 != "Relay.swift" }

            case "index-support":
                edited["sources"] = sources + ["Relay.swift"]

            default:
                break
            }
            return edited
        }
        let written = try JSONSerialization.data(withJSONObject: object, options: [.prettyPrinted, .sortedKeys])
        return String(bytes: written, encoding: .utf8) ?? ""
    }

    /// Scans a copy of the Index fixture as set up, on a thread of its
    /// own, and passes the copy and what the scan gave to `check`.
    func run(check: (BuildFixture, IndexGroupHarness.Outcome) throws -> Void) async throws {
        let setup = self
        let scanned = try await ThreadRun { Result { try setup.scanned() } }.value.get()
        defer { scanned.remove() }
        try check(scanned.fixture, scanned.outcome)
    }

    /// Makes the toolchain and the copy and scans the copy as set up.
    private func scanned() throws -> IndexFixtureScanned {
        let toolchain = try FakeToolchain.make(build: scenario)
        let fixture: BuildFixture
        do {
            fixture = try BuildFixture()
        } catch {
            toolchain.remove()
            throw error
        }
        do {
            return IndexFixtureScanned(fixture: fixture, outcome: try scan(fixture, with: toolchain))
        } catch {
            toolchain.remove()
            fixture.remove()
            throw error
        }
    }

    /// `fixture` scanned with `toolchain` as set up.
    private func scan(_ fixture: BuildFixture, with toolchain: FakeToolchain) throws -> IndexGroupHarness.Outcome {
        if hasLibrary {
            try Data().write(to: toolchain.directory.appendingPathComponent("usr/lib/libIndexStore.dylib"))
        }
        let root = fixture.package.root
        try IndexGroupHarness.configuration(toolchain, extra: extra)
            .write(to: root.appendingPathComponent(".swiftstats.yml"), atomically: true, encoding: .utf8)
        try prepare(fixture)
        let recording = try IndexFixture.data(dump)
        let paths = Self.restoring(fixture)
        let transform = source
        let scanner = PackageScanner(describer: fixture.package.describer, tools: SnapshotHarness.noTools)
            .readingIndex { _, _ in
                try transform(RecordedIndexSource(recording: recording, restoring: paths))
            }
        let snapshot = try SnapshotScanner(scanner: scanner, build: SnapshotHarness.build)
            .scan(
                packageAt: root,
                configurationFile: StoreLocation.localConfiguration(packageRoot: root),
                git: SnapshotHarness.git(commit: "c1"),
                toolchain: SnapshotHarness.toolchain,
                date: SnapshotHarness.date,
                history: .skipped("test"),
                tiers: RequestedTiers(index: true)
            )
        return IndexGroupHarness.Outcome(snapshot: snapshot, toolchain: toolchain, root: root)
    }
}
