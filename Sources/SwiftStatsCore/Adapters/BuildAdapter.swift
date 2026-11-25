//
//  BuildAdapter.swift
//  SwiftStatsCore
//
//  The `build` collector (M7, design §1): SwiftStats' own T1 build of the
//  package, in `.swiftstats/index-build`, which gives the type-check
//  timings, the compiler warnings and the index store the `index` and
//  `periphery` collectors read. The three run only when asked for with
//  `scan --index`, never in `backfill`, in `diff`'s scans of other
//  revisions or with `--rerun`; every scan lists their statuses, so a
//  snapshot says how to run them when it didn't. The build's `swift` is
//  the coverage collector's (`collectors.coverage.path`, else PATH), as
//  SwiftMutator's test command's is, so it takes no `path` of its own. Its
//  run finds the toolchain that `swift` selects in the package root, then
//  runs `BuildSession`'s commands with that toolchain's own `swift`; its
//  identity is that `swift`'s version line, as the coverage run's is.
//

import Foundation

/// The `build` collector's name, statuses, options and run, and the reason
/// the T1 group shares when a scan didn't ask for it.
enum BuildAdapter {
    /// The collector's name in a snapshot and in `.swiftstats.yml`.
    static let name = "build"
    /// Why a scan that didn't ask for the T1 group skipped each of its
    /// collectors (`build`, `index` and `periphery` alike).
    static let notRequestedReason = "not requested; scan --index runs it"
    /// Why a requested build is skipped until the T1 session is wired into
    /// the scan (a placeholder; design §13, removed in step 3c).
    static let notBuiltReason = "the index build is not built yet"
    /// The error `collectors.build.path` gives: the build has no
    /// executable of its own.
    static let pathError = "the build uses the coverage collector's swift; set collectors.coverage.path"
    /// The first option: the build's command, with the build directory as
    /// the package sees it.
    static let invocation = (["swift"] + BuildSession.arguments(scratch: ".swiftstats/\(BuildSession.directoryName)"))
        .joined(separator: " ")
    /// The second option: what each build deletes first.
    static let rebuildOption = "rebuild: root package intermediates"
    /// How many changed files the changed-files warning names.
    private static let namedChangedFiles = 5

    /// The options of a run on the package at `root` before its toolchain
    /// is known: the command, what it rebuilds and the toolchain pin.
    static func options(root: URL) -> [String] {
        [invocation, rebuildOption, SwiftInferCopy.toolchainOption(root: root)]
    }

    /// Builds the package at `root` with the toolchain `swift` resolves to
    /// there, hashes `files`, the scanned files, again, and returns what
    /// `readProducts` makes of the run. `index.lock` is taken after the
    /// toolchain is found and held until `readProducts` returns, so the
    /// whole T1 group (reading the build's output, the index store and
    /// outskirts) runs under it (design §1.2); `readProducts` is called
    /// with the failed run when another scan holds it.
    static func run<Value>(
        swift: URL,
        root: URL,
        files: [FileRecord],
        then readProducts: (BuildRun) throws -> Value
    ) rethrows -> Value {
        var toolchain: SwiftToolchain?
        var lock: IndexLock?
        defer { lock?.release() }
        let (outcome, milliseconds) = Stopwatch.time {
            Result { () throws -> BuildSession.Products in
                let directory = try StoreLocation.ignoreDirectory(packageRoot: root)
                let build = directory.appendingPathComponent(BuildSession.directoryName)
                let found = try SwiftToolchain.discover(
                    swift: swift,
                    command: CoverageCommand(root: root, build: build, toolchain: nil)
                )
                toolchain = found
                lock = try IndexLock(file: directory.appendingPathComponent(BuildSession.lockName))
                let scratch = try BuildSession.realPath(creating: build)
                let command = CoverageCommand(root: root, build: scratch, toolchain: found.directory)
                return try BuildSession(toolchain: found, command: command, files: files).run()
            }
        }
        return try readProducts(
            buildRun(outcome, milliseconds: milliseconds, toolchain: toolchain, swift: swift, root: root)
        )
    }

    /// The run that `outcome` was, taking `milliseconds`, with the
    /// `toolchain` found (nil when it wasn't) from `swift` for the package
    /// at `root`.
    private static func buildRun(
        _ outcome: Result<BuildSession.Products, any Error>,
        milliseconds: Int,
        toolchain: SwiftToolchain?,
        swift: URL,
        root: URL
    ) -> BuildRun {
        let known = options(root: root) + (toolchain.map { ["toolchain: \($0.swiftVersion)"] } ?? [])
        let identity = toolchain.map { CoverageAdapter.identity(versionLine: $0.swiftVersion) }
        switch outcome {
        case .success(let products):
            let changed = products.changedFiles
            let notes = products.notes + (changed.isEmpty ? [] : [changedNote(changed.count)])
            return BuildRun(
                status: CollectorStatus(
                    name: name,
                    state: .ran,
                    version: toolchain?.swiftVersion,
                    reason: notes.isEmpty ? nil : notes.joined(separator: "; "),
                    options: known + ["map: " + TimingMapper.rule, "warnings: " + WarningReader.rule]
                ),
                executable: toolchain?.swift,
                identity: identity,
                milliseconds: milliseconds,
                warnings: changed.isEmpty ? [] : [changedWarning(changed)],
                products: products
            )

        case .failure(let error):
            let reason = (error as? CoverageFailure)?.description
                ?? SwiftInferTargetRun.reason(for: error, replacing: [(root, CoverageCommand.packagePlaceholder)])
            return BuildRun(
                status: CollectorStatus(name: name, state: .failed, version: nil, reason: reason, options: known),
                executable: toolchain?.swift ?? swift,
                identity: identity,
                milliseconds: milliseconds,
                warnings: [],
                products: nil
            )
        }
    }

    /// The reason's note for `count` scanned files changed during the
    /// scan.
    private static func changedNote(_ count: Int) -> String {
        count == 1 ? "1 file changed during the scan" : "\(count) files changed during the scan"
    }

    /// The warning for the scanned files `changed` during the scan, naming
    /// the first five.
    private static func changedWarning(_ changed: [String]) -> ScanWarning {
        let named = changed.prefix(namedChangedFiles).joined(separator: ", ")
        let more = changed.count > namedChangedFiles ? " and \(changed.count - namedChangedFiles) more" : ""
        return ScanWarning(
            file: nil,
            message: "\(name): \(changedNote(changed.count)); their records get no USR, timing, warnings "
                + "or dead-code mapping: \(named)\(more)"
        )
    }
}
