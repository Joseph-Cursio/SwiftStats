import Foundation
@testable import SwiftStatsCore
import Testing

/// The T1 group run by a scan (M7, design §1.5, §1.8): the build runs with
/// the coverage collector's `swift`'s toolchain and is recorded with its
/// version as identity; the index and outskirts are skipped needing the
/// build when it didn't run and fail when it wrote no index store; when it
/// ran, the index reads its store (here failing for a toolchain without
/// `libIndexStore.dylib`; `USRJoinTests` reads a recorded one) and
/// outskirts gives its placeholder. `IndexGroupOutputTests` reads a
/// recorded build. A fake toolchain acts out every build.
@Suite("Index group")
struct IndexGroupTests {
    /// The build's options when it ran, the toolchain's `swift` being the
    /// fake's and the package pinning no toolchain (design §1.8).
    private static let ranOptions = [
        "swift build --build-tests --build-system swiftbuild -c debug -v --no-color-diagnostics "
            + "--scratch-path .swiftstats/index-build -Xswiftc -index-include-locals "
            + "-Xswiftc -Xfrontend -Xswiftc -debug-time-function-bodies "
            + "-Xswiftc -Xfrontend -Xswiftc -debug-time-expression-type-checking "
            + "-Xswiftc -Xfrontend -Xswiftc -debug-diagnostic-names",
        "rebuild: root package intermediates",
        ".swift-version: absent",
        "toolchain: Apple Swift version 9.9 (fake)",
        "map: " + TimingMapper.rule,
        "warnings: " + WarningReader.rule
    ]

    @Test("""
        asked for with a swift and an outskirts found, the build runs with the coverage collector's swift's \
        toolchain whatever coverage's enabled says, the index reads its store, failing for a toolchain without \
        libIndexStore.dylib, and periphery gives its placeholder, outskirts never run
        """)
    func buildRuns() throws {
        let outskirts = try IndexGroupHarness.outskirts()
        defer { try? FileManager.default.removeItem(at: outskirts.deletingLastPathComponent()) }
        let extra = "    enabled: false\n  periphery:\n    path: \(outskirts.path)\n"

        try IndexGroupHarness.scanSmall(
            try IndexGroupHarness.emptyBuild(),
            extra: extra,
            tiers: RequestedTiers(index: true),
            tools: SnapshotHarness.noTools
        ) { outcome in
            let build = try #require(outcome.statuses["build"])
            #expect(build.state == .ran)
            #expect(build.reason == nil)
            #expect(build.version == "Apple Swift version 9.9 (fake)")
            #expect(build.options == Self.ranOptions)
            #expect(outcome.statuses["index"]?.reason
                == "the toolchain has no libIndexStore.dylib (<toolchain>/usr/lib)")
            #expect(outcome.statuses["periphery"]?.reason == "the outskirts collector is not built yet")
            #expect(outcome.statuses["index"]?.state == .failed && outcome.statuses["periphery"]?.state == .skipped)
            #expect(outcome.report.index == nil)
            #expect(outcome.built)
            #expect(outcome.toolchain.calls(of: "proxy") == ["-print-target-info"])
            #expect(outcome.report.collectors.first { $0.name == "coverage" }?.reason
                == CoverageAdapter.notRequestedReason)
            let log = outskirts.deletingLastPathComponent().appendingPathComponent("arguments.log")
            #expect(FileManager.default.fileExists(atPath: log.path) == false)
            let report = try #require(outcome.report.build)
            #expect(report.records.isEmpty && report.attachments.isEmpty)
            #expect(report.totals == BuildTotals(functionEntries: 0, expressionEntries: 0, milliseconds: 0))
            #expect(report.complete)
        }
    }

    @Test("""
        the build's run is recorded with the toolchain's swift version as its identity, its options as it ran, \
        the index with the reader's pinned revision, and no identity for outskirts, which didn't run
        """)
    func identities() throws {
        try IndexGroupHarness.scanSmall(
            try IndexGroupHarness.emptyBuild(),
            extra: "",
            tiers: RequestedTiers(index: true),
            tools: SnapshotHarness.noTools
        ) { outcome in
            let build = try #require(outcome.run("build"))
            #expect(build.identity == "swift:Apple Swift version 9.9 (fake)")
            #expect(build.identityLabel == nil)
            #expect(build.version == "Apple Swift version 9.9 (fake)")
            #expect(build.options == Self.ranOptions)
            #expect(build.state == .ran)
            #expect(outcome.run("index")?.identity == "git:64aa0b26913249c4e7c21d351a215fba02702003")
            #expect(outcome.run("periphery")?.identity == nil)
        }
    }

    @Test("""
        a build skipped for its settings or for no swift leaves the index and periphery skipped needing it, \
        after their own settings, and runs nothing
        """)
    func buildSkipped() throws {
        let outskirts = try IndexGroupHarness.outskirts()
        defer { try? FileManager.default.removeItem(at: outskirts.deletingLastPathComponent()) }
        let periphery = "  periphery:\n    path: \(outskirts.path)\n"

        try IndexGroupHarness.scanSmall(
            try IndexGroupHarness.emptyBuild(),
            extra: "  build:\n    enabled: false\n" + periphery,
            tiers: RequestedTiers(index: true),
            tools: SnapshotHarness.noTools
        ) { outcome in
            let needs = "needs the build: skipped, disabled by collectors.build.enabled"
            #expect(outcome.statuses.mapValues(\.reason) == [
                "build": "disabled by collectors.build.enabled", "index": needs, "periphery": needs
            ])
            #expect(outcome.statuses.values.allSatisfy { $0.state == .skipped && $0.options.isEmpty })
            #expect(outcome.toolchain.calls(of: "proxy").isEmpty && outcome.toolchain.calls(of: "swift").isEmpty)
            #expect(outcome.report.build == nil)
            #expect(outcome.run("build")?.identity == nil)
        }
        try IndexGroupHarness.scanSmall(
            try IndexGroupHarness.emptyBuild(),
            extra: "  build:\n    enabled: false\n  index:\n    enabled: false\n" + periphery,
            tiers: RequestedTiers(index: true),
            tools: SnapshotHarness.noTools
        ) { outcome in
            #expect(outcome.statuses["index"]?.reason == "disabled by collectors.index.enabled")
        }
    }

    @Test("""
        a failed build leaves the index and periphery skipped needing it, with its reason, no build block and \
        no swiftc counts in the roll-ups
        """)
    func buildFailed() throws {
        var scenario = try IndexGroupHarness.emptyBuild()
        scenario.stderr = "error: no such module 'Missing'\n"
        scenario.status = 1
        let outskirts = try IndexGroupHarness.outskirts()
        defer { try? FileManager.default.removeItem(at: outskirts.deletingLastPathComponent()) }

        try IndexGroupHarness.scanSmall(
            scenario,
            extra: "  periphery:\n    path: \(outskirts.path)\n",
            tiers: RequestedTiers(index: true),
            tools: SnapshotHarness.noTools
        ) { outcome in
            let reason = "swift build exited 1: error: no such module 'Missing'"
            let needs = "needs the build: failed, " + reason
            #expect(outcome.statuses.mapValues(\.reason) == ["build": reason, "index": needs, "periphery": needs])
            #expect(outcome.statuses["build"]?.state == .failed)
            #expect(outcome.statuses["build"]?.options == Array(Self.ranOptions.prefix(4)))
            #expect(outcome.run("build")?.identity == "swift:Apple Swift version 9.9 (fake)")
            #expect(outcome.report.build == nil)
            #expect(outcome.report.rollups.allSatisfy { $0.findings["swiftc"] == nil })
        }
    }

    @Test("""
        a build that ran without writing an index store fails the index and periphery, saying so, and keeps \
        its own results
        """)
    func noStore() throws {
        var scenario = try IndexGroupHarness.emptyBuild()
        scenario.makesStore = false
        let outskirts = try IndexGroupHarness.outskirts()
        defer { try? FileManager.default.removeItem(at: outskirts.deletingLastPathComponent()) }

        try IndexGroupHarness.scanSmall(
            scenario,
            extra: "  periphery:\n    path: \(outskirts.path)\n",
            tiers: RequestedTiers(index: true),
            tools: SnapshotHarness.noTools
        ) { outcome in
            let failure = "the build wrote no index store at <build>/out"
            #expect(outcome.statuses["build"]?.state == .ran)
            #expect(outcome.report.build != nil)
            #expect(outcome.statuses["index"] == CollectorStatus(
                name: "index",
                state: .failed,
                version: nil,
                reason: failure,
                options: []
            ))
            #expect(outcome.statuses["periphery"]?.state == .failed)
            #expect(outcome.statuses["periphery"]?.reason == failure)
        }
    }

    @Test("""
        a build whose output can't be read fails, saying so without absolute paths, its options stopping at \
        the toolchain, and the index needs it
        """)
    func unreadableOutput() throws {
        var scenario = try IndexGroupHarness.emptyBuild()
        scenario.script = "rm \"$scratch/swiftstats-build.log\"\n"

        try IndexGroupHarness.scanSmall(
            scenario,
            extra: "",
            tiers: RequestedTiers(index: true),
            tools: SnapshotHarness.noTools
        ) { outcome in
            let build = try #require(outcome.statuses["build"])
            let reason = try #require(build.reason)
            #expect(build.state == .failed)
            #expect(reason.hasPrefix("could not read the build's output: "))
            #expect(reason.contains("swiftstats-build.log"))
            #expect(reason.contains(outcome.root.lastPathComponent) == false)
            #expect(build.options == Array(Self.ranOptions.prefix(4)))
            #expect(outcome.statuses["index"]?.reason == "needs the build: failed, " + reason)
            #expect(outcome.report.build == nil)
        }
    }
}
