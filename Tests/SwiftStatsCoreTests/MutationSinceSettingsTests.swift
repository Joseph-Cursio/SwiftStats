import Foundation
@testable import SwiftStatsCore
import Testing

/// The `--since` guards on settings and the package manifest (M6, design
/// §6.1 refusal 5, review findings 12, 22 and 26). Before anything runs,
/// results made with another time limit, another `.swift-version` or
/// another SDK environment are refused, naming the setting, as is a base
/// whose package manifest (`Package.swift`, `Package@swift-*.swift`)
/// differs from the scanned tree's, changed, added or deleted, since which
/// files SwiftMutator compiles and mutates may differ while their bytes
/// don't. After the run, a test executable other than the base's fails
/// the collector, naming both, and merges and keeps nothing.
@Suite("Mutation since settings and manifest guards")
struct MutationSinceSettingsTests {
    /// A change made before a `--since main` scan of the `since` branch,
    /// and the refusal expected.
    struct Change: CustomTestStringConvertible, Sendable {
        /// What changes.
        let name: String
        /// The settings added under `collectors.swiftmutator`.
        var settings = ""
        /// The full run's header text replaced, and its replacement.
        var header: (recorded: String, changed: String)?
        /// Makes the change in the repository at the given root, once
        /// the `since` branch is checked out.
        var edit: @Sendable (URL) throws -> Void = { _ in
            // Nothing to edit.
        }
        /// The refusal's reason.
        let reason: String

        /// The row's name in the test's report.
        var testDescription: String {
            name
        }
    }

    /// The recorded header's toolchain block, as it starts.
    private static let toolchain = #""toolchain":{"environment":{}"#

    /// The settings changes refusal 5 catches before SwiftMutator starts.
    static let settingsChanges = [
        Change(
            name: "another time limit",
            settings: "    options:\n      timeout: 5\n",
            reason: "the results of main were made with other settings (timeout); run a full scan --mutation"
        ),
        Change(
            name: "a .swift-version added",
            edit: { root in
                let pin = root.appendingPathComponent(".swift-version")
                try "6.4.1\n".write(to: pin, atomically: true, encoding: .utf8)
            },
            reason: "the results of main were made with other settings (.swift-version); run a full scan --mutation"
        ),
        Change(
            name: "another SDK environment",
            header: (toolchain, #""toolchain":{"environment":{"DEVELOPER_DIR":"/Elsewhere/Xcode.app"}"#),
            reason: "the results of main were made with other settings (sdk environment); run a full scan --mutation"
        )
    ]

    /// The manifest changes refused before SwiftMutator starts, either way
    /// round: a file stops being compiled, or may start.
    static let manifestChanges = [
        Change(
            name: "Package.swift edited to exclude a file, uncommitted",
            edit: { root in
                let manifest = root.appendingPathComponent("Package.swift")
                let text = try String(contentsOf: manifest, encoding: .utf8).replacingOccurrences(
                    of: #".target(name: "Core"),"#,
                    with: #".target(name: "Core", exclude: ["Dormant.swift"]),"#
                )
                try text.write(to: manifest, atomically: true, encoding: .utf8)
            },
            reason: "Package.swift changed since main, so the files SwiftMutator compiles and mutates may differ "
                + "from those of its results; run a full scan --mutation"
        ),
        Change(
            name: "a versioned manifest committed",
            edit: { root in
                try FileManager.default.copyItem(
                    at: root.appendingPathComponent("Package.swift"),
                    to: root.appendingPathComponent("Package@swift-6.4.swift")
                )
                try MutationFixture.git(["add", "Package@swift-6.4.swift"], in: root, day: 3)
                try MutationFixture.git(["commit", "--quiet", "--message", "Manifest"], in: root, day: 3)
            },
            reason: "Package@swift-6.4.swift changed since main, so the files SwiftMutator compiles and mutates may "
                + "differ from those of its results; run a full scan --mutation"
        ),
        Change(
            name: "a versioned manifest untracked",
            edit: { root in
                try FileManager.default.copyItem(
                    at: root.appendingPathComponent("Package.swift"),
                    to: root.appendingPathComponent("Package@swift-6.0.swift")
                )
            },
            reason: "Package@swift-6.0.swift changed since main, so the files SwiftMutator compiles and mutates may "
                + "differ from those of its results; run a full scan --mutation"
        )
    ]

    /// Whether scanning the `since` branch of `harness` with `--since main`
    /// in `workspace`, once `change` is made, throws its refusal without
    /// running SwiftMutator or storing anything.
    private static func refuses(
        _ harness: SinceHarness,
        change: Change,
        in workspace: SnapshotWorkspace
    ) throws -> Bool {
        try harness.repository.checkOut("since")
        try change.edit(harness.root)
        try harness.fake.act(SinceHarness.scenario("since"))
        let runs = harness.runs()
        let latest = try workspace.store.latestSnapshotID(package: "Mutation", packagePath: "")
        var thrown: (any Error)?
        do {
            _ = try workspace.scanWorkingTree(
                history: .skipped("test"),
                tiers: RequestedTiers(mutation: .since("main"))
            )
        } catch {
            thrown = error
        }
        let stored = try workspace.store.latestSnapshotID(package: "Mutation", packagePath: "")
        return thrown as? StoreError == .noMutationBase(change.reason) && harness.runs() == runs && stored == latest
    }

    /// Stores the base, the full run's header changed as `change` says,
    /// then checks that `change` is refused.
    private static func check(_ change: Change) throws {
        let harness = try SinceHarness()
        defer { harness.remove() }
        var full = try SinceHarness.scenario("full")
        if let header = change.header {
            full.results = full.results?.replacingOccurrences(of: header.recorded, with: header.changed)
            #expect(full.results?.contains(header.changed) == true)
        }
        _ = try harness.scan("main", acting: full, request: .full, in: harness.workspace)
        let workspace = change.settings.isEmpty ? harness.workspace : try harness.workspace(adding: change.settings)

        #expect(try Self.refuses(harness, change: change, in: workspace))
    }

    @Test(
        """
        results made with another time limit, .swift-version or SDK environment are refused before anything runs, \
        naming the setting
        """,
        arguments: settingsChanges
    )
    func otherSettings(change: Change) throws {
        try Self.check(change)
    }

    @Test(
        """
        a package manifest that differs from the base's commit, edited, committed or untracked, is refused before \
        anything runs, since which files are compiled and mutated may have changed
        """,
        arguments: manifestChanges
    )
    func manifestChanged(change: Change) throws {
        try Self.check(change)
    }

    @Test("the manifests changed since a commit include a deleted one, and only the package's own count")
    func manifests() throws {
        let harness = try SinceHarness()
        defer { harness.remove() }
        try harness.repository.checkOut("since")
        let unchanged = try MutationChanges.manifests(in: harness.root, since: harness.mainCommit)
        try FileManager.default.removeItem(at: harness.root.appendingPathComponent("Package.swift"))

        let deleted = try MutationChanges.manifests(in: harness.root, since: harness.mainCommit)

        #expect(unchanged.isEmpty)
        #expect(deleted == ["Package.swift"])
        #expect(MutationChanges.isManifest("Package@swift-5.9.swift"))
        #expect(MutationChanges.isManifest("Nested/Package.swift") == false)
        #expect(MutationChanges.isManifest("Nested/Package@swift-5.9.swift") == false)
        #expect(MutationChanges.isManifest("Sources/Core/Package.swift.orig") == false)
    }

    @Test("""
        a run whose test executable differs from the base's fails the collector naming both, merging and keeping \
        nothing and leaving no pending run
        """)
    func otherTestExecutable() throws {
        let harness = try SinceHarness()
        defer { harness.remove() }
        let recorded = String(repeating: "a", count: 64)
        let tested = String(repeating: "b", count: 64)
        var full = try SinceHarness.scenario("full")
        full.results = full.results?.replacingOccurrences(
            of: Self.toolchain,
            with: Self.toolchain + #","testExecutableSHA256":"\#(recorded)""#
        )
        _ = try harness.scan("main", acting: full, request: .full, in: harness.workspace)
        var scenario = try SinceHarness.scenario("since")
        scenario.results = scenario.results?.replacingOccurrences(
            of: Self.toolchain,
            with: Self.toolchain + #","testExecutableSHA256":"\#(tested)""#
        )

        let since = try harness.scan("since", acting: scenario, request: .since("main"), in: harness.workspace)

        let status = since.snapshot.info.collectors.first { $0.name == MutationAdapter.name }
        #expect(status?.state == .failed)
        #expect(status?.reason == "the run's test executable (sha256:\(tested)) differs from that of the results of "
            + "main (sha256:\(recorded))")
        #expect(since.snapshot.report.mutation == nil)
        let directory = harness.root.appendingPathComponent(".swiftstats/mutation")
        #expect(FileManager.default.fileExists(atPath: directory.appendingPathComponent("pending.json").path) == false)
    }
}
