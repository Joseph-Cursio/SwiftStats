//
//  SnapshotWorkspace+Backfill.swift
//  SwiftStatsCore
//
//  `backfill` (PRD §7.13, §10): T0 snapshots of past first-parent commits,
//  so trends start with history rather than waiting for scans to build up.
//  Each commit is exported as `diff` exports one, and scanned without
//  history and, by default, without the external tools, which are slow.
//  Only commits holding the package's manifest are picked from. Picks are
//  fixed: every Nth commit counts from the first commit holding the
//  package, and a week's pick is its latest commit by committer time in
//  UTC, so a later run only adds new points. A snapshot that holds results
//  a backfill doesn't collect (history, coverage, mutation results, tools,
//  the dependency graph) is never replaced; one holding history, coverage
//  or mutation results, which a backfill never collects, isn't even
//  rescanned. Snapshots are stored as every scan is (`save(_:drop:)`).
//

import Foundation

extension SnapshotWorkspace {
    /// Collectors whose results a backfill never collects: it reads no
    /// history and never runs the tests, with coverage or mutated.
    private static let neverCollected: Set<String> = [
        HistoryCollector.name, CoverageAdapter.name, MutationAdapter.name
    ]
    /// Why a backfill without tools skips the external collectors.
    static let backfillToolSkipReason = "backfill runs SwiftStats only; --with-tools adds the tools"
    /// Collectors whose results a backfill without tools doesn't collect.
    private static let toolCollectors: Set<String> = [
        SwiftLintAdapter.name, SwiftProjectLintAdapter.name, SwiftInferPropertiesAdapter.name,
        SwiftCloneDetectorAdapter.name
    ]

    /// The commits `plan` picks from `line` (oldest first), oldest first.
    static func picks(_ line: [(commit: String, time: Int)], plan: BackfillPlan) -> [String] {
        var picked: [(commit: String, time: Int)]
        switch plan.selection {
        case .every(let step):
            picked = line.enumerated().filter { entry in entry.offset.isMultiple(of: max(1, step)) }.map(\.element)

        case .weekly:
            var calendar = Calendar(identifier: .iso8601)
            calendar.timeZone = .gmt
            var latest: [String: (index: Int, time: Int)] = [:]
            for (index, entry) in line.enumerated() {
                let components = calendar.dateComponents(
                    [.yearForWeekOfYear, .weekOfYear],
                    from: Date(timeIntervalSince1970: TimeInterval(entry.time))
                )
                let week = "\(components.yearForWeekOfYear ?? 0)-\(components.weekOfYear ?? 0)"
                if let current = latest[week], current.time > entry.time {
                    continue
                }
                latest[week] = (index, entry.time)
            }
            picked = latest.values.map(\.index).sorted().map { line[$0] }
        }
        if let since = plan.since {
            picked = picked.filter { $0.time >= since }
        }
        if let maximum = plan.maximumCommits {
            picked = Array(picked.suffix(maximum))
        }
        return picked.map(\.commit)
    }

    /// The step for a commit kept because its snapshot holds results of
    /// the collectors `names` that a backfill wouldn't collect.
    private static func kept(_ commit: String, holding names: Set<String>) -> BackfillStep {
        BackfillStep(
            commit: commit,
            action: .kept,
            note: "its snapshot holds \(names.sorted().joined(separator: ", ")); rescan it with `swiftstats scan`"
        )
    }

    /// The committer time of the commit `revision` names, or nil.
    public func committerTime(of revision: String) -> Int? {
        let arguments = HistoryCollector.committerTimeArguments(of: "\(revision)^{commit}")
        return GitReader.line(arguments, in: root).flatMap { Int($0) }
    }

    /// Backfills the commits `plan` picks, reporting each step to `progress`.
    public func backfill(_ plan: BackfillPlan, progress: (BackfillStep) -> Void) throws -> [BackfillStep] {
        let name = try describer.describePackage(at: root).name
        let git = GitReader.read(packageRoot: root, ignoring: storeInPackage)
        guard git.commit != nil else {
            throw StoreError.noSnapshot("\(name): backfill follows git history, and this package has none")
        }
        let backfillScanner = SnapshotScanner(
            scanner: PackageScanner(
                describer: describer,
                tools: scanner.scanner.tools,
                toolSkipReason: plan.withTools ? nil : Self.backfillToolSkipReason
            ),
            build: scanner.build
        )
        var steps: [BackfillStep] = []
        let line = try holdingPackage(try firstParentLine(), packagePath: git.packagePath)
        for commit in Self.picks(line, plan: plan) {
            let step = backfillStep(commit, git: git, plan: plan, scanner: backfillScanner)
            progress(step)
            steps.append(step)
        }
        return steps
    }

    /// The commits of `line` whose tree holds the manifest of the package at
    /// `packagePath`, read with one `git cat-file --batch-check`.
    func holdingPackage(
        _ line: [(commit: String, time: Int)],
        packagePath: String
    ) throws -> [(commit: String, time: Int)] {
        guard line.isEmpty == false else {
            return []
        }
        let manifest = packagePath.isEmpty ? "Package.swift" : "\(packagePath)/Package.swift"
        let list = FileManager.default.temporaryDirectory
            .appendingPathComponent("SwiftStats-manifests-\(UUID().uuidString)")
        ScratchRegistry.shared.track(list)
        defer { ScratchRegistry.shared.remove(list) }
        try Data(line.map { "\($0.commit):\(manifest)\n" }.joined().utf8).write(to: list)
        let output = try ProcessRunner.run(
            executable: GitReader.git,
            arguments: ["--no-optional-locks", "cat-file", "--batch-check=%(objecttype)"],
            in: root,
            input: list
        )
        let answers = (String(bytes: output, encoding: .utf8) ?? "").split(separator: "\n")
        return zip(line, answers).filter { $0.1 == "blob" }.map(\.0)
    }

    /// Backfills one commit.
    private func backfillStep(
        _ commit: String,
        git: GitState,
        plan: BackfillPlan,
        scanner backfillScanner: SnapshotScanner
    ) -> BackfillStep {
        do {
            var existingRan: Set<String> = []
            if let existing = try store.snapshotID(packagePath: git.packagePath, commit: commit, isDirty: false) {
                let info = try store.info(id: existing)
                let own = info.collectors.first { $0.name == SwiftStatsCollector.name }
                guard plan.rerun, own?.identity != backfillScanner.build.identity else {
                    return BackfillStep(commit: commit, action: .skipped, note: "already has a snapshot")
                }
                existingRan = Set(info.collectors.filter { $0.state == .ran }.map(\.name))
                let held = existingRan.filter { name in
                    Self.neverCollected.contains(name)
                        || (plan.withTools == false && Self.toolCollectors.contains(name))
                }
                if held.isEmpty == false {
                    return Self.kept(commit, holding: held)
                }
            }
            let (snapshot, note) = try scanExport(
                commit,
                git: git,
                scanner: backfillScanner,
                history: .skipped("backfill")
            )
            let ran = Set(snapshot.info.collectors.filter { $0.state == .ran }.map(\.name))
            let lost = existingRan.subtracting(ran)
            guard lost.isEmpty else {
                return Self.kept(commit, holding: lost)
            }
            try save(snapshot, drop: [])
            return BackfillStep(commit: commit, action: .scanned, note: note)
        } catch {
            return BackfillStep(commit: commit, action: .failed, note: String(describing: error))
        }
    }
}
