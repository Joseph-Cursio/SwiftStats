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
    /// What `UnrunNotice`'s line about a requested build that didn't run
    /// says first, before `failed` or `was skipped`.
    static let ownRunLead = "this scan's index build "
    /// What the reason of a collector reading the build (`index`,
    /// `periphery`) starts with when the build didn't run.
    static let needsBuildLead = "needs the build: "
    /// The error `collectors.build.path` gives: the build has no
    /// executable of its own.
    static let pathError = "the build uses the coverage collector's swift; set collectors.coverage.path"
    /// The first option: the build's command, with the build directory as
    /// the package sees it.
    static let invocation = (["swift"] + BuildSession.arguments(scratch: ".swiftstats/\(BuildSession.directoryName)"))
        .joined(separator: " ")
    /// The second option: what each build deletes first.
    static let rebuildOption = "rebuild: root package intermediates"
    /// What the options naming the mapping rules start with: a run that
    /// ran records them, after the toolchain.
    static let ruleOptionLeads = ["map: ", "warnings: "]
    /// How many changed files the changed-files warning names.
    private static let namedChangedFiles = 5

    /// The options of a run on the package at `root` before its toolchain
    /// is known: the command, what it rebuilds and the toolchain pin.
    static func options(root: URL) -> [String] {
        [invocation, rebuildOption, SwiftInferCopy.toolchainOption(root: root)]
    }

    /// What becomes of collector `name`, which reads the build (`index` or
    /// `periphery`), after `run`, once its own settings let it run:
    /// skipped `needs the build: <state>, <reason>` when the build didn't
    /// run (design §1.5), failed when it ran without writing an index
    /// store (§1.3 step 10); nil when it may read the build.
    static func dependent(_ name: String, after run: BuildRun) -> AdapterResult? {
        switch run.status.state {
        case .ran:
            guard let failure = run.products?.storeFailure else {
                return nil
            }
            return AdapterResult(
                status: CollectorStatus(name: name, state: .failed, version: nil, reason: failure, options: []),
                findings: [],
                warnings: []
            )

        case .failed, .skipped:
            let how = run.status.state.rawValue + (run.status.reason.map { ", " + $0 } ?? "")
            return .skipped(name, reason: needsBuildLead + how)
        }
    }

    /// What became of a requested build that ended as `state` for
    /// `reason`, as `UnrunNotice` words it; nil when it ran.
    static func ownRun(state: CollectorState, reason given: String?) -> String? {
        let reason = given ?? "no reason given"
        switch state {
        case .ran:
            return nil

        case .failed:
            return "\(ownRunLead)failed (\(reason))"

        case .skipped:
            return reason == notRequestedReason ? nil : "\(ownRunLead)was skipped (\(reason))"
        }
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
        var log: URL?
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
                return try BuildSession(toolchain: found, command: command, files: files).run { log = $0 }
            }
        }
        var run = buildRun(outcome, milliseconds: milliseconds, toolchain: toolchain, swift: swift, root: root)
        run.log = log
        return try readProducts(run)
    }

    /// The run that `outcome` was, taking `milliseconds`, with the
    /// `toolchain` found (nil when it wasn't) from `swift` for the package
    /// at `root`; its task log isn't set.
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
                    options: known + zip(ruleOptionLeads, [TimingMapper.rule, WarningReader.rule]).map { $0 + $1 }
                ),
                executable: toolchain?.swift,
                identity: identity,
                milliseconds: milliseconds,
                warnings: changed.isEmpty ? [] : [changedWarning(changed)],
                products: products,
                log: nil
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
                products: nil,
                log: nil
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
