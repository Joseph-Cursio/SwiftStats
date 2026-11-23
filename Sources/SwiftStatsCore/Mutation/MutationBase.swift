//
//  MutationBase.swift
//  SwiftStatsCore
//
//  The stored snapshot `scan --mutation --since <rev>` merges with (M6,
//  design §6.1): the clean snapshot of the commit `<rev>` names, at the
//  package's path. It is chosen before anything runs and refused, first
//  reason that applies, when there is none; when it holds no mutation
//  results (naming the nearest first-parent ancestor of HEAD whose clean
//  snapshot holds complete ones); when its results are incomplete; when its commit isn't
//  an ancestor of HEAD, so files changed on both sides would have no
//  results; and when this scan's SwiftMutator build or settings differ
//  from the ones its results were made with, since SwiftMutator itself
//  won't combine results across builds; and when a package manifest
//  changed since its commit, since which files SwiftMutator compiles and
//  mutates may have changed with it while their bytes didn't, so their
//  carried results could hold rows a full run wouldn't, or lack rows it
//  would. Once the run is over, its
//  header is checked against the base again (a binary replaced during the
//  run): the same build, operators and test executable, and the merge
//  base it compared with must be the base's commit. A resumed `--since`
//  run chooses its base again, by the commit its pending record names,
//  and is refused when that snapshot's results changed or are gone.
//

import Foundation

/// The stored snapshot a `--since` run merges with, and its results.
struct MutationBase: Hashable, Sendable {
    /// Where to find the base: the store and the package in it.
    struct Lookup {
        /// The store.
        let store: SnapshotStore
        /// The package's name.
        let package: String
        /// The package root.
        let root: URL
        /// The package's git state, as the scan reads it.
        let git: GitState
    }

    /// The variables of the SDK environment SwiftMutator records, which it
    /// inherits from SwiftStats.
    static let environmentKeys: Set<String> = ["DEVELOPER_DIR", "SDKROOT", "TOOLCHAINS"]
    /// How many hex digits of a commit a reason shows.
    static let shortCommitLength = 10
    /// The options a run's settings give before it runs that a base's
    /// options must match, by name.
    private static let comparedOptions = ["arguments", "timeout", ".swift-version", "toolchain", "sdk environment"]
    /// The options a results header gives.
    private static let headerOptions = ["toolchain", "test executable", "sdk environment", "operators", "coverage"]

    /// The revision as given on the command line, or the first ten hex
    /// digits of a full commit given, as a resumed run's record names it.
    let revision: String
    /// The commit it names: the base snapshot's.
    let commit: String
    /// The base snapshot's mutation results.
    let report: MutationReport
    /// The base snapshot's swiftmutator options.
    let options: [String]

    /// The base as the merged results name it.
    var source: MutationSource {
        MutationSource(commit: commit, collectedAt: report.collectedAt)
    }

    /// The commit's first ten hex digits, as reasons show it.
    var shortCommit: String {
        String(commit.prefix(Self.shortCommitLength))
    }

    /// The build every run of the base's results was made with; nil when
    /// they name none, or more than one.
    var identity: String? {
        common(\.identity).flatMap(\.self)
    }

    /// SwiftMutator's version, as the base's runs record it.
    var version: String? {
        common(\.version)
    }

    /// The options a results header gives (`toolchain`, `test executable`,
    /// `sdk environment`, `operators`, `coverage`), as the base recorded
    /// them: what a run that left no results file reports, since it ran
    /// the base's build with the base's settings.
    var recordedHeaderOptions: [String] {
        options.filter { Self.headerOptions.contains(Self.name(of: $0)) }
    }

    /// The name of option `option`: its text before the first `: `.
    static func name(of option: String) -> String {
        option.range(of: ": ").map { String(option[..<$0.lowerBound]) } ?? option
    }

    /// `commit`'s first ten hex digits.
    static func short(_ commit: String) -> String {
        String(commit.prefix(shortCommitLength))
    }

    /// The base the revision `given` names, looked up as `lookup` says; a
    /// refusal saying why there is none (`StoreError.noMutationBase`). A
    /// full commit, as a resume gives, is shown by its first ten hex
    /// digits.
    static func select(revision given: String, lookup: Lookup) throws -> Self {
        guard lookup.git.commit != nil else {
            throw StoreError.noMutationBase("--since needs git, and \(lookup.package) isn't in a repository")
        }
        guard let resolved = RevisionExport.commit(of: given, in: lookup.root) else {
            throw StoreError.noMutationBase("\(given) names no commit")
        }
        let shown = given == resolved ? short(resolved) : given
        let named = given == resolved ? shown : "\(shown) (\(short(resolved)))"
        guard let snapshot = try lookup.store.snapshotID(
            package: lookup.package,
            packagePath: lookup.git.packagePath,
            commit: resolved,
            isDirty: false
        ) else {
            throw StoreError.noMutationBase("no snapshot of \(named); run scan --mutation at \(shown) first")
        }
        guard let held = try lookup.store.mutationResults(id: snapshot) else {
            throw StoreError.noMutationBase(try noResultsReason(named: named, revision: shown, lookup: lookup))
        }
        guard held.results.report.complete else {
            throw StoreError.noMutationBase("the results of \(named) are incomplete; run a full scan --mutation")
        }
        guard GitReader.output(["merge-base", "--is-ancestor", resolved, "HEAD"], in: lookup.root) != nil else {
            throw StoreError.noMutationBase(
                "\(shown) isn't an ancestor of HEAD, so files changed on both sides would have no results"
            )
        }
        return Self(revision: shown, commit: resolved, report: held.results.report, options: held.run.options)
    }

    /// Why the base of `named` (`<rev> (<commit10>)`) holding no mutation
    /// results is refused: naming the nearest first-parent ancestor of
    /// HEAD whose clean snapshot holds complete ones, if any.
    private static func noResultsReason(named: String, revision: String, lookup: Lookup) throws -> String {
        let holding = try lookup.store.commitsHoldingMutation(
            package: lookup.package,
            packagePath: lookup.git.packagePath
        )
        let history = GitReader.output(["rev-list", "--first-parent", "HEAD", "--"], in: lookup.root)
            .flatMap { String(bytes: $0, encoding: .utf8) } ?? ""
        let nearest = history.split(separator: "\n").map(String.init).first(where: holding.contains)
        let advice = nearest.map { "--since \(short($0)), the nearest ancestor of HEAD whose snapshot holds them, can" }
            ?? "run scan --mutation at \(revision) first, which can then"
        return "the snapshot of \(named) holds no mutation results; \(advice) be the base"
    }

    /// The base a resume of the pending `--since` run `pending` merges
    /// with, looked up as `lookup` says: chosen again by the commit it
    /// recorded, and refused when that snapshot's results changed or are
    /// gone.
    static func resumed(_ pending: PendingMutationRun.Base, lookup: Lookup) throws -> Self {
        let base: Self
        do {
            base = try select(revision: pending.commit, lookup: lookup)
        } catch {
            let reason = if case StoreError.noMutationBase(let inner) = error { inner } else { "\(error)" }
            throw StoreError.noMutationBase(
                "the base of that run, \(short(pending.commit)), no longer has the results it started from "
                    + "(\(reason)); run scan --mutation --since \(short(pending.commit))"
            )
        }
        guard base.report.collectedAt == pending.collectedAt else {
            throw StoreError.noMutationBase(
                "the results of the base of that run, \(base.shortCommit), have changed since it started; "
                    + "run scan --mutation --since \(base.shortCommit)"
            )
        }
        return base
    }

    /// The toolchain line `swift --version` prints in the package at
    /// `root`, which reads its `.swift-version` as the copy's test command
    /// does; nil when it prints none.
    static func toolchainLine(swift: URL, root: URL) -> String? {
        guard let data = try? ProcessRunner.run(executable: swift.path, arguments: ["--version"], in: root),
              let text = String(bytes: data, encoding: .utf8) else {
            return nil
        }
        return text.split(whereSeparator: \.isNewline).first.map(String.init)
    }

    /// The SDK environment `environment` gives SwiftMutator: its
    /// `DEVELOPER_DIR`, `SDKROOT` and `TOOLCHAINS` as set.
    static func sdkEnvironment(of environment: [String: String]) -> [String: String] {
        environment.filter { environmentKeys.contains($0.key) }
    }

    /// Why a run of `mutator`, with `settings`, whose tests' `swift` prints
    /// `toolchain` for its version, in the package at `root` under the SDK
    /// environment `environment`, can't merge with this base: results no
    /// run made, another SwiftMutator build, or the first option of
    /// `comparedOptions` that differs; nil when it can.
    func settingsRefusal(
        mutator: URL,
        settings: CollectorSettings?,
        toolchain: String?,
        root: URL,
        environment: [String: String]
    ) -> String? {
        // A full run that found nothing to test leaves results with no run
        // to compare the build and settings with.
        guard report.runs.isEmpty == false else {
            return "the results of \(revision) come from a run that found no code SwiftMutator could test; "
                + "run a full scan --mutation"
        }
        let build = ContentHash.sha256(ofFileAt: mutator).map { "sha256:\($0)" }
        guard let identity, build == identity else {
            return "the results of \(revision) were made with another SwiftMutator build; run a full scan --mutation"
        }
        let current = MutationAdapter.options(settings: settings, root: root) + [
            "toolchain: " + (toolchain ?? "unrecorded"),
            "sdk environment: " + MutationAdapter.sdkEnvironment(environment)
        ]
        let recorded = Dictionary(options.map { (Self.name(of: $0), $0) }) { first, _ in first }
        for option in current where Self.comparedOptions.contains(Self.name(of: option)) {
            let name = Self.name(of: option)
            if recorded[name] != option {
                return "the results of \(revision) were made with other settings (\(name)); run a full scan --mutation"
            }
        }
        return nil
    }

    /// Why a run in the package at `root` can't merge with this base: a
    /// manifest (`Package.swift`, `Package@swift-*.swift`) differs from
    /// the base's commit, or the files changed since couldn't be listed;
    /// nil when it can.
    func manifestRefusal(root: URL) -> String? {
        let changed: [String]
        do {
            changed = try MutationChanges.manifests(in: root, since: commit)
        } catch {
            return error.description
        }
        guard changed.isEmpty == false else {
            return nil
        }
        return "\(changed.joined(separator: ", ")) changed since \(revision), so the files SwiftMutator compiles "
            + "and mutates may differ from those of its results; run a full scan --mutation"
    }

    /// Why a run whose results header gave `facts` can't merge with this
    /// base after all, naming both values: another SwiftMutator build,
    /// other operators, another test executable (when both record one),
    /// or a merge base other than the base's commit; nil when it can.
    func postRunRefusal(_ facts: MutationRunFacts) -> String? {
        let build = facts.executableSHA256.map { "sha256:\($0)" }
        if build != identity {
            return "the run was made by SwiftMutator \(build ?? "unrecorded"), "
                + "but the results of \(revision) by \(identity ?? "unrecorded")"
        }
        let operators = common(\.operators)
        if facts.operators.sorted() != operators {
            return "the run's operators (\(facts.operators.sorted().joined(separator: ", "))) differ from "
                + "those of the results of \(revision) (\((operators ?? []).joined(separator: ", ")))"
        }
        if let tested = facts.testExecutableSHA256, let recorded = common(\.testExecutableSHA256).flatMap(\.self),
           tested != recorded {
            return "the run's test executable (sha256:\(tested)) differs from that of the results of "
                + "\(revision) (sha256:\(recorded))"
        }
        let mergeBase = facts.since?.mergeBase
        guard mergeBase == commit else {
            return "the run compared the tree with \(mergeBase.map(Self.short) ?? "no merge base") rather than "
                + "\(shortCommit), the commit of the results of \(revision)"
        }
        return nil
    }

    /// The value every run of the base's results has at `path`; nil when
    /// they have none, or differ.
    private func common<Value: Equatable>(_ path: KeyPath<MutationRunRecord, Value>) -> Value? {
        let values = report.runs.map { $0[keyPath: path] }
        guard let first = values.first, values.allSatisfy({ $0 == first }) else {
            return nil
        }
        return first
    }
}
