//
//  HistoryCollector.swift
//  SwiftStatsCore
//
//  The history collector (TH, PRD §7.13). From one walk over the commits
//  behind the analysed commit, it parses every changed version of the
//  package's Swift files, works out what each commit did to each function
//  family, and traces every family of the scan back through those events.
//  Everything is relative to the analysed commit's committer date, never
//  the clock, so a commit's history is the same whenever it is read.
//

import Foundation

/// Collects history.
enum HistoryCollector {
    /// The collector's name in a snapshot.
    static let name = "history"
    /// Blobs read and parsed at a time, to bound memory.
    private static let batchSize = 2_000
    /// Seconds in a day.
    static let day = 86_400
    /// The fields of a first-parent log line: time, parents and subject.
    private static let mergeLogFieldCount = 3
    /// The position of the subject among a first-parent log line's fields.
    private static let subjectField = 2
    /// One merge commit in this many first-parent commits makes a merge-style repository.
    private static let mergeStyleShare = 5
    /// One numbered commit in this many makes a squash-style repository.
    private static let squashStyleShare = 2

    /// The status of a scan that didn't ask for history.
    static let notRequested = skipped("not requested")

    /// The status of a skipped history run.
    static func skipped(_ reason: String) -> CollectorStatus {
        CollectorStatus(name: name, state: .skipped, version: nil, reason: reason, options: [])
    }

    /// The version string of the git that reads history.
    static func gitVersion(in directory: URL) -> String? {
        GitReader.line(["--version"], in: directory)
    }

    /// The history of `input`.
    static func collect(_ input: HistoryInput) throws -> HistoryReport {
        let top = input.top
        let tree = try GitHistoryWalk.files(top: top, commit: input.commit, packagePath: input.packagePath)
        let modules = ModuleMap(targets: input.targets, anchorTree: Set(tree.keys), excluded: input.excluded)
        let commits = try GitHistoryWalk.commits(top: top, commit: input.commit, packagePath: input.packagePath)
        let anchor = try anchorTime(of: input)
        let windowStart = anchor - input.options.windowDays * day
        let classifier = CommitClassifier(
            options: input.options,
            ignored: CommitClassifier.ignoreRevs(in: ignoreFileText(of: input)),
            windowStart: windowStart,
            modules: modules
        )
        let anchorFiles = tree.filter { modules.place($0.key) != nil }
        let parsed = try parseVersions(commits: commits, anchorFiles: anchorFiles, modules: modules, top: top)
        let events = Parallel.map(Array(commits.indices)) { index in
            Self.events(of: commits[index], parsed: parsed, modules: modules)
        }
        let facts = commits.map(classifier.facts(of:))
        let log = commitLog(commits, facts)
        let seeds = side(anchorFiles.map { (path: $0.key, blob: $0.value) }, parsed: parsed)
        let chain = HistoryChain(
            seeds: FunctionFamily.families(seeds.rows),
            scan: FunctionFamily.families(input.records.map { FunctionRow($0, snapshotId: 0) }),
            events: events
        )
        let measures = HistoryMeasures(
            chain: chain,
            facts: facts,
            anchor: anchor,
            options: input.options,
            tests: TestNameMatcher(testFiles: anchorFiles.keys.filter { modules.place($0)?.isTest == true }),
            generated: Set(input.files.filter(\.generated).map(\.path)),
            logOrdinals: log.ordinals
        )
        return HistoryReport(
            commit: input.commit,
            date: date(anchor),
            windowDays: input.options.windowDays,
            windowStart: date(windowStart),
            mergeStyle: mergeStyle(top: top, commit: input.commit, since: windowStart),
            commits: log.entries.count,
            windowCommits: facts.filter { $0.files > 0 && $0.inWindow }.count,
            commitLog: log.entries,
            fixCommits: notes(commits, facts, events) { $0.matchesFix },
            revertCommits: notes(commits, facts, events) { $0.isRevertCommit },
            sweepCommits: notes(commits, facts, events) { $0.isSweep },
            families: measures.families(),
            coupling: measures.coupling(minimumSupport: input.options.couplingMinSupport),
            warnings: (shallowWarnings(top: top) + chain.warnings).sorted()
        )
    }

    /// The commits that changed the package's Swift files, newest first, and
    /// the position among them of each one's index in `commits`.
    private static func commitLog(
        _ commits: [HistoryCommit],
        _ facts: [CommitFacts]
    ) -> (entries: [HistoryLogEntry], ordinals: [Int: Int]) {
        let logged = commits.indices.filter { facts[$0].files > 0 }
        let entries = logged.map { index in
            HistoryLogEntry(
                hash: commits[index].hash,
                date: date(commits[index].time),
                sweep: facts[index].isSweep,
                fix: facts[index].isFix
            )
        }
        let ordinals = Dictionary(uniqueKeysWithValues: logged.enumerated().map { ($0.element, $0.offset) })
        return (entries, ordinals)
    }

    /// The committer time of the analysed commit.
    private static func anchorTime(of input: HistoryInput) throws -> Int {
        guard let anchorText = GitReader.line(committerTimeArguments(of: input.commit), in: input.top),
              let anchor = Int(anchorText) else {
            throw ScanError.commandFailed("git show \(input.commit)", -1, "no committer date")
        }
        return anchor
    }

    /// The git arguments printing `commit`'s committer time alone, whatever
    /// the user's configuration says about signatures.
    static func committerTimeArguments(of commit: String) -> [String] {
        ["-c", "log.showSignature=false", "show", "-s", "--no-show-signature", "--no-color", "--format=%ct", commit]
    }

    /// The text of the analysed commit's `.git-blame-ignore-revs`, empty when it has none.
    private static func ignoreFileText(of input: HistoryInput) -> String {
        GitReader.output(["show", "\(input.commit):.git-blame-ignore-revs"], in: input.top)
            .flatMap { data in String(bytes: data, encoding: .utf8) } ?? ""
    }

    /// A warning when the repository is a shallow clone.
    private static func shallowWarnings(top: URL) -> [String] {
        guard GitReader.line(["rev-parse", "--is-shallow-repository"], in: top) == "true" else {
            return []
        }
        return ["the repository is a shallow clone, so history stops at its oldest commit"]
    }

    /// `time` as snapshots write dates.
    static func date(_ time: Int) -> String {
        SnapshotScanner.format(Date(timeIntervalSince1970: TimeInterval(time)))
    }

    /// Every version of every in-scope file the commits and the anchor
    /// hold, parsed, by `blob + "\0" + path`.
    private static func parseVersions(
        commits: [HistoryCommit],
        anchorFiles: [String: String],
        modules: ModuleMap,
        top: URL
    ) throws -> [String: HistoryFile] {
        var wanted: [String: WantedFile] = [:]
        let add: (String?, String?) -> Void = { path, blob in
            guard let path, let blob, let place = modules.place(path) else {
                return
            }
            wanted[blob + "\u{0}" + path] = WantedFile(
                blob: blob,
                path: path,
                module: place.module,
                isTest: place.isTest
            )
        }
        for change in commits.flatMap(\.changes) {
            add(change.oldPath, change.oldBlob)
            add(change.newPath, change.newBlob)
        }
        for (path, blob) in anchorFiles {
            add(path, blob)
        }
        let files = wanted.keys.sorted().compactMap { key in wanted[key] }
        var parsed: [String: HistoryFile] = [:]
        var start = 0
        while start < files.count {
            let batch = Array(files[start..<min(start + batchSize, files.count)])
            let contents = try BlobReader.read(Array(Set(batch.map(\.blob))).sorted(), top: top)
            parsed.merge(HistoryParser.parseAll(batch, contents: contents)) { first, _ in first }
            start += batchSize
        }
        return parsed
    }

    /// The parsed rows and line hashes of `files` (path and blob).
    private static func side(_ files: [(path: String, blob: String)], parsed: [String: HistoryFile]) -> CommitSide {
        var side = CommitSide()
        for file in files {
            guard let history = parsed[file.blob + "\u{0}" + file.path] else {
                continue
            }
            side.rows += history.rows
            for (key, hashes) in history.lines {
                side.lines[file.path + "\u{0}" + key] = hashes
            }
        }
        return side
    }

    /// What `commit` did to the families of its changed files.
    private static func events(
        of commit: HistoryCommit,
        parsed: [String: HistoryFile],
        modules: ModuleMap
    ) -> [HistoryEvent] {
        var oldFiles: [(path: String, blob: String)] = []
        var newFiles: [(path: String, blob: String)] = []
        var moduleMoves: [String: String] = [:]
        for change in commit.changes {
            let oldPlace = change.oldPath.flatMap(modules.place)
            let newPlace = change.newPath.flatMap(modules.place)
            if let path = change.oldPath, let blob = change.oldBlob, oldPlace != nil {
                oldFiles.append((path, blob))
            }
            if let path = change.newPath, let blob = change.newBlob, newPlace != nil {
                newFiles.append((path, blob))
            }
            if let path = change.oldPath, let oldPlace, let newPlace, oldPlace.module != newPlace.module {
                moduleMoves[path] = newPlace.module
            }
        }
        guard oldFiles.isEmpty == false || newFiles.isEmpty == false else {
            return []
        }
        return HistoryMatcher.events(
            old: side(oldFiles, parsed: parsed),
            new: side(newFiles, parsed: parsed),
            moduleMoves: moduleMoves
        )
    }

    /// Notes on the window's commits that `include` picks, among those that
    /// changed the package's Swift files.
    private static func notes(
        _ commits: [HistoryCommit],
        _ facts: [CommitFacts],
        _ events: [[HistoryEvent]],
        include: (CommitFacts) -> Bool
    ) -> [HistoryCommitNote] {
        commits.indices.filter { facts[$0].files > 0 && facts[$0].inWindow && include(facts[$0]) }.map { index in
            HistoryCommitNote(
                commit: commits[index].hash,
                date: date(commits[index].time),
                subject: commits[index].subject,
                files: facts[index].files,
                families: events[index].filter { $0.changed && $0.new != nil }.count,
                excluded: facts[index].exclusion
            )
        }
    }

    /// How the repository merges, from its first-parent commits since
    /// `since` (or all of them, when none is that recent).
    private static func mergeStyle(top: URL, commit: String, since: Int) -> MergeStyle {
        let arguments = [
            "-c", "log.showSignature=false", "log", "--first-parent", "--no-show-signature", "--no-color",
            "--no-mailmap", "--format=%ct%x00%P%x00%s", commit
        ]
        let lines = GitReader.output(arguments, in: top)
            .map { data in (String(bytes: data, encoding: .utf8) ?? "").split(separator: "\n") } ?? []
        let entries = lines.map { line in line.split(separator: "\u{0}", omittingEmptySubsequences: false) }
            .filter { fields in fields.count == mergeLogFieldCount }
        let recent = entries.filter { fields in (Int(fields[0]) ?? 0) >= since }
        let sample = recent.isEmpty ? entries : recent
        guard sample.isEmpty == false else {
            return .linear
        }
        let merges = sample.filter { fields in fields[1].split(separator: " ").count > 1 }.count
        if merges * mergeStyleShare >= sample.count {
            return .merge
        }
        let numbered = sample.filter { fields in
            fields[subjectField].range(of: #"\(#\d+\)\s*$"#, options: .regularExpression) != nil
        }.count
        return numbered * squashStyleShare >= sample.count ? .squash : .linear
    }
}
