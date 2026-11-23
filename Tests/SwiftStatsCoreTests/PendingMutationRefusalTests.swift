import Foundation
@testable import SwiftStatsCore
import Testing

/// When `scan --mutation --resume` refuses a pending SwiftMutator run
/// (M6, design §1.7): when it leaves other files out of the tree than the
/// run did, when the tree's git state differs from the run's (its commit,
/// its uncommitted changes or the package's path, but not the branch),
/// when an effective setting differs (the tools found,
/// `collectors.swiftmutator.arguments`, `options.workers` and
/// `options.timeout`), naming the first, when a file the run's scan
/// parsed changed, was added or is gone, outside git too. A `--since`
/// run's record refuses nothing more: its base is chosen again by `scan`
/// (`MutationBase.resumed`).
@Suite("Mutation resume refusals")
struct PendingMutationRefusalTests {
    /// A row of the refusal table: what differs from the pending run, and
    /// the refusal it gives.
    struct Refusal: CustomTestStringConvertible, Sendable {
        /// What differs.
        let name: String
        /// The tree's git state.
        let git: GitState
        /// The settings now; nil when they aren't compared.
        let settings: PendingMutationRun.Settings?
        /// The pending run's mode.
        let mode: PendingMutationRun.Mode
        /// The refusal expected; nil when the resume may go on.
        let reason: String?
        /// The files the resume leaves out of the tree.
        var ignoring: [String] = []

        /// The row's name in the test report.
        var testDescription: String {
            name
        }
    }

    /// A row of the scanned-files table: what a scan of the resume parsed,
    /// named by what changed, and whether the resume is refused.
    struct Scan: CustomTestStringConvertible, Sendable {
        /// What changed.
        let name: String
        /// The hashes the scan read, by path.
        let scanned: [String: String]
        /// Whether the resume is refused.
        let refused: Bool

        /// The row's name in the test report.
        var testDescription: String {
            name
        }
    }

    /// The source file the pending run's scan parsed.
    static let sourcePath = "Sources/Lib/Lib.swift"
    /// Its text.
    static let source = "public func one() -> Int { 1 }\n"
    /// The files the pending run's scan parsed, with their hashes.
    static let scanned = [sourcePath: ContentHash.sha256(Data(source.utf8))]
    /// The scanned-files table.
    static let scans = [
        Scan(name: "nothing changed", scanned: scanned, refused: false),
        Scan(
            name: "the file changed",
            scanned: [sourcePath: ContentHash.sha256(Data("public func one() -> Int { 2 }\n".utf8))],
            refused: true
        ),
        Scan(
            name: "a file was added",
            scanned: scanned.merging(["Sources/Lib/More.swift": "00"]) { first, _ in first },
            refused: true
        ),
        Scan(name: "the file is gone", scanned: [:], refused: true)
    ]

    /// The commit the pending run of the refusal table started at.
    static let commit = "0123456789abcdef0123456789abcdef01234567"
    /// The tree it started in.
    static let git = tree()
    /// Its settings.
    static let settings = makeSettings(arguments: ["--skip", "slow"], workers: 2, timeout: 30)
    /// The refusal table.
    static let refusals: [Refusal] = [
        Refusal(name: "nothing differs", git: git, settings: settings, mode: .full, reason: nil),
        Refusal(
            name: "another branch at the same commit",
            git: tree(branch: "other"),
            settings: settings,
            mode: .full,
            reason: nil
        ),
        Refusal(name: "settings not compared", git: git, settings: nil, mode: .full, reason: nil),
        Refusal(
            name: "another commit",
            git: tree(commit: "f" + commit.dropFirst()),
            settings: settings,
            mode: .full,
            reason: PendingMutationRun.treeChangedReason
        ),
        Refusal(
            name: "other uncommitted changes",
            git: tree(dirtyHash: "d2"),
            settings: settings,
            mode: .full,
            reason: PendingMutationRun.treeChangedReason
        ),
        Refusal(
            name: "the changes committed",
            git: tree(dirtyHash: nil),
            settings: settings,
            mode: .full,
            reason: PendingMutationRun.treeChangedReason
        ),
        Refusal(
            name: "another package path",
            git: tree(packagePath: "Other"),
            settings: settings,
            mode: .full,
            reason: PendingMutationRun.treeChangedReason
        ),
        Refusal(
            name: "outside git",
            git: .outsideGit,
            settings: settings,
            mode: .full,
            reason: PendingMutationRun.treeChangedReason
        ),
        Refusal(
            name: "another swift-mutator",
            git: git,
            settings: makeSettings(
                arguments: ["--skip", "slow"],
                workers: 2,
                timeout: 30,
                mutator: "/other/swift-mutator"
            ),
            mode: .full,
            reason: changed("the swift-mutator found")
        ),
        Refusal(
            name: "another swift",
            git: git,
            settings: makeSettings(arguments: ["--skip", "slow"], workers: 2, timeout: 30, swift: "/other/swift"),
            mode: .full,
            reason: changed("the swift found for its tests")
        ),
        Refusal(
            name: "other arguments",
            git: git,
            settings: makeSettings(arguments: [], workers: 2, timeout: 30),
            mode: .full,
            reason: changed("collectors.swiftmutator.arguments")
        ),
        Refusal(
            name: "other workers",
            git: git,
            settings: makeSettings(arguments: ["--skip", "slow"], workers: nil, timeout: 30),
            mode: .full,
            reason: changed("collectors.swiftmutator.options.workers")
        ),
        Refusal(
            name: "another time limit",
            git: git,
            settings: makeSettings(arguments: ["--skip", "slow"], workers: 2, timeout: 30.5),
            mode: .full,
            reason: changed("collectors.swiftmutator.options.timeout")
        ),
        Refusal(
            name: "the tree and a setting both changed",
            git: .outsideGit,
            settings: makeSettings(arguments: [], workers: 2, timeout: 30),
            mode: .full,
            reason: PendingMutationRun.treeChangedReason
        ),
        Refusal(
            name: "other files left out",
            git: git,
            settings: settings,
            mode: .full,
            reason: PendingMutationRun.ignoringChangedReason,
            ignoring: ["stats.sqlite"]
        ),
        Refusal(
            name: "other files left out and other uncommitted changes",
            git: tree(dirtyHash: "d2"),
            settings: settings,
            mode: .full,
            reason: PendingMutationRun.ignoringChangedReason,
            ignoring: ["stats.sqlite"]
        ),
        Refusal(name: "nothing, in a --since run", git: git, settings: settings, mode: .since, reason: nil)
    ]

    /// The pending run's tree with `commit`, `branch`, `dirtyHash` (clean
    /// when nil) or `packagePath` changed.
    private static func tree(
        commit: String = Self.commit,
        branch: String = "main",
        dirtyHash: String? = "d1",
        packagePath: String = "Pkg"
    ) -> GitState {
        GitState(
            commit: commit,
            branch: branch,
            isDirty: dirtyHash != nil,
            dirtyHash: dirtyHash,
            packagePath: packagePath
        )
    }

    /// Settings of `mutator` and `swift` with `arguments`, `workers` and
    /// `timeout`.
    private static func makeSettings(
        arguments: [String],
        workers: Int?,
        timeout: Double?,
        mutator: String = "/tools/swift-mutator",
        swift: String = "/tools/swift"
    ) -> PendingMutationRun.Settings {
        PendingMutationRun.Settings(
            mutator: URL(fileURLWithPath: mutator),
            swift: URL(fileURLWithPath: swift),
            settings: CollectorSettings(
                enabled: true,
                path: nil,
                arguments: arguments,
                workers: workers,
                timeout: timeout
            )
        )
    }

    /// The refusal naming `setting` as the first that changed.
    static func changed(_ setting: String) -> String {
        "the settings have changed since that run started (\(setting)); run scan --mutation"
    }

    /// The pending run of the refusal table, in `mode`.
    static func pending(_ mode: PendingMutationRun.Mode) -> PendingMutationRun {
        PendingMutationRun(
            startedAt: "2026-11-21T07:32:00Z",
            commit: commit,
            dirtyHash: "d1",
            packagePath: "Pkg",
            mode: mode,
            base: nil,
            resultsFile: nil,
            project: "Repo/Pkg",
            command: ["run"],
            settings: settings,
            copyFixed: 0,
            ignoring: [],
            scanned: scanned
        )
    }

    @Test(
        """
        a resume is refused when the files left out of the tree, its git state or a setting differs from the \
        pending run's, naming the files left out first, then the tree, then the first setting that differs; the \
        branch alone and the mode don't matter
        """,
        arguments: refusals
    )
    func refusal(row: Refusal) {
        #expect(Self.pending(row.mode).refusal(git: row.git, ignoring: row.ignoring, settings: row.settings)
            == row.reason)
    }

    @Test(
        "after the scan, a resume is refused when a file the run's scan parsed changed, was added or is gone",
        arguments: scans
    )
    func scannedFiles(row: Scan) {
        let reason = Self.pending(.full).treeRefusal(.scanned(row.scanned))
        #expect(reason == (row.refused ? PendingMutationRun.treeChangedReason : nil))
    }

    @Test("""
        before the scan, a resume is refused when a file the run's scan parsed no longer holds its bytes in the \
        package or is gone, which says so outside git, where the git state can't
        """)
    func packageFiles() throws {
        let package = try TemporaryPackage([Self.sourcePath: Self.source])
        defer { package.remove() }
        let pending = Self.pending(.full)
        let file = package.root.appendingPathComponent(Self.sourcePath)

        let unchanged = pending.treeRefusal(.package(package.root))
        try "public func one() -> Int { 2 }\n".write(to: file, atomically: true, encoding: .utf8)
        let edited = pending.treeRefusal(.package(package.root))
        try FileClone.remove(file)
        let gone = pending.treeRefusal(.package(package.root))

        #expect(unchanged == nil)
        #expect(edited == PendingMutationRun.treeChangedReason)
        #expect(gone == PendingMutationRun.treeChangedReason)
    }
}
