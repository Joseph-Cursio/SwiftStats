//
//  PendingMutationRun.swift
//  SwiftStatsCore
//
//  The SwiftMutator run `scan --mutation --resume` can continue (M6,
//  design §1.7), recorded in `.swiftstats/mutation/pending.json`. A run
//  writes it just before SwiftMutator starts, without the results file,
//  which only SwiftMutator names: an interrupted scan ends with
//  SwiftMutator, before it could learn it, and leaves the record for a
//  resume, which then finds the file in SwiftMutator's log folder in the
//  kept copy. Once the run has been judged, the record names the results
//  file when the run failed with one a resume can continue (a readable
//  header, design §1.5), and is removed otherwise, except after a run that
//  ran in a scan that stores its snapshot: then it names the results kept
//  in `runs/<id>/` (`kept`) until the snapshot is stored, so a save that is
//  refused can be resumed without running SwiftMutator again (design §6.4,
//  as built); the copy has ended by then. It holds the git state
//  the run's copy was made from, the mode and base, the copy's project
//  folder inside `work/` (from which SwiftMutator's log folder follows),
//  the command, the effective settings, how many files the copy fixed,
//  the files the run left out of its git state and its copy, and the
//  SHA-256 of each file its scan parsed. A resume is refused when there is
//  no record, when it leaves out other files, when the tree's git state
//  differs from it, when the settings do, or when a file the scan parsed
//  changed, was added or is gone: outside git, or for a file git ignores,
//  the git state can't say so, and the kept copy holds the run's bytes,
//  which SwiftMutator compares a resume against (its exit 5).
//

import Foundation

/// A SwiftMutator run a resume can continue, as `pending.json` records it.
struct PendingMutationRun: Codable, Equatable, Sendable {
    /// Which run it was.
    enum Mode: String, Codable, Sendable {
        /// A run of every mutant.
        case full
        /// A run of the files changed since a stored snapshot's commit.
        case since
    }

    /// What a resume checks the files the run's scan parsed against.
    enum ScannedFiles: Sendable {
        /// The hashes the resume's own scan read, by path from the
        /// package root.
        case scanned([String: String])
        /// The package's files as they are now, at the package root
        /// given, before the resume's scan has run.
        case package(URL)
    }

    /// The stored snapshot a `--since` run merges with.
    struct Base: Codable, Equatable, Sendable {
        /// The snapshot's commit.
        let commit: String
        /// When it was collected.
        let collectedAt: String
    }

    /// The results of a run that ran, kept until its scan's snapshot is
    /// stored, and what the step said of them that the results file
    /// doesn't hold.
    struct Kept: Codable, Equatable, Sendable {
        /// The kept results file, from the package root
        /// (`.swiftstats/mutation/runs/<id>/results.jsonl`), beside which
        /// the JSON report is kept when there was one.
        let resultsFile: String
        /// The exit's own note; nil when it had none.
        let reason: String?
        /// The warnings the step gave.
        let warnings: [ScanWarning]
        /// A `--since` run's selection (`MutationChanges.selection`);
        /// empty for a full run.
        let selection: [String]
    }

    /// The effective settings a resume must find again: the tools
    /// resolved and `collectors.swiftmutator`'s values.
    struct Settings: Codable, Equatable, Sendable {
        /// The `swift-mutator` run, by its path.
        let mutator: String
        /// The `swift` of the test command, by its path.
        let swift: String
        /// `collectors.swiftmutator.arguments`.
        let arguments: [String]
        /// `collectors.swiftmutator.options.workers`; nil for SwiftMutator's.
        let workers: Int?
        /// `collectors.swiftmutator.options.timeout`; nil for SwiftMutator's.
        let timeout: Double?

        /// The settings of a run of `mutator` whose tests run `swift`,
        /// under `settings` (nil when `.swiftstats.yml` has none).
        init(mutator: URL, swift: URL, settings: CollectorSettings?) {
            self.mutator = mutator.path
            self.swift = swift.path
            arguments = settings?.arguments ?? []
            workers = settings?.workers
            timeout = settings?.timeout
        }

        /// The first setting that differs from `recorded`'s, as a reason
        /// names it; nil when none does.
        func difference(from recorded: Self) -> String? {
            if mutator != recorded.mutator {
                return "the swift-mutator found"
            }
            if swift != recorded.swift {
                return "the swift found for its tests"
            }
            if arguments != recorded.arguments {
                return "collectors.swiftmutator.arguments"
            }
            if workers != recorded.workers {
                return "collectors.swiftmutator.options.workers"
            }
            if timeout != recorded.timeout {
                return "collectors.swiftmutator.options.timeout"
            }
            return nil
        }
    }

    /// Why a resume is refused when no run is pending.
    static let noneReason = "no interrupted or failed SwiftMutator run to resume"
    /// Why it is refused when the tree's git state, or a file the scan
    /// parsed, changed.
    static let treeChangedReason = "the tree has changed since that run started; run scan --mutation"
    /// Why it is refused when the run left other files out of its git
    /// state and its copy than the resume does, so the two can't be
    /// compared.
    static let ignoringChangedReason =
        "that run left other files out of the tree (scan --no-store, or the store moved); run scan --mutation"
    /// Why the resume of a `--since` run is refused when the scan has no
    /// base for it to merge with.
    static let noBaseReason = "resuming a --since run merges with its base snapshot, and this scan has none"
    /// How `startedAt` is written.
    static let dateFormat = Date.ISO8601FormatStyle(timeZone: .gmt)

    /// When the run started (ISO 8601, UTC).
    let startedAt: String
    /// The commit its copy checked out; nil outside git.
    let commit: String?
    /// The hash of the uncommitted changes laid over it; nil when clean.
    let dirtyHash: String?
    /// The package's path from its repository's top level.
    let packagePath: String
    /// The run's mode.
    let mode: Mode
    /// The snapshot a `--since` run merges with; nil for a full run.
    let base: Base?
    /// The results file, relative to `work/`; nil until the run was judged.
    let resultsFile: String?
    /// The copy's project folder, relative to `work/`.
    let project: String
    /// SwiftMutator's arguments, `run` first.
    let command: [String]
    /// The effective settings.
    let settings: Settings
    /// How many scanned files the copy took from the package because git
    /// checked them out with other bytes.
    let copyFixed: Int
    /// The files in the package, relative to its root, the run left out
    /// of its git state and its copy (a store kept in the package).
    let ignoring: [String]
    /// The SHA-256 of each file the run's scan parsed, by its path from
    /// the package root.
    let scanned: [String: String]
    /// The results of a run that ran, kept until its scan's snapshot is
    /// stored; nil for a run a resume continues.
    var kept: Kept?

    /// The record in `directory`; nil when there is none, a failure when
    /// it doesn't read.
    static func read(in directory: MutationDirectory) throws(MutationFailure) -> Self? {
        guard FileClone.exists(directory.pending) else {
            return nil
        }
        do {
            return try JSONDecoder().decode(Self.self, from: Data(contentsOf: directory.pending))
        } catch {
            throw MutationFailure(description: "\(MutationDirectory.pendingName) doesn't read; run scan --mutation")
        }
    }

    /// Removes the record in `directory`, if there is one.
    static func remove(in directory: MutationDirectory) throws(MutationFailure) {
        do {
            try FileClone.remove(directory.pending)
        } catch {
            throw MutationWorkCopy.failure("remove .swiftstats/mutation/\(MutationDirectory.pendingName)", error)
        }
    }

    /// The record naming `resultsFile`, relative to `work/`.
    func naming(resultsFile file: String) -> Self {
        Self(
            startedAt: startedAt,
            commit: commit,
            dirtyHash: dirtyHash,
            packagePath: packagePath,
            mode: mode,
            base: base,
            resultsFile: file,
            project: project,
            command: command,
            settings: settings,
            copyFixed: copyFixed,
            ignoring: ignoring,
            scanned: scanned
        )
    }

    /// The record of the run that ran and left `kept`.
    func keeping(_ kept: Kept) -> Self {
        var record = self
        record.kept = kept
        return record
    }

    /// Why a resume of this run is refused in a tree whose state is `git`,
    /// read leaving out the files at `ignored`, under `settings`, which
    /// aren't compared when nil; nil when it isn't.
    func refusal(git: GitState, ignoring ignored: [String], settings current: Settings?) -> String? {
        guard ignored == ignoring else {
            return Self.ignoringChangedReason
        }
        guard git.commit == commit, git.dirtyHash == dirtyHash, git.packagePath == packagePath else {
            return Self.treeChangedReason
        }
        if let current, let changed = current.difference(from: settings) {
            return "the settings have changed since that run started (\(changed)); run scan --mutation"
        }
        return nil
    }

    /// Why a resume of this run is refused when the files its scan parsed
    /// are now `files`: the tree changed when one of them differs, was
    /// added (seen only once the resume's scan has run) or is gone; nil
    /// when none did.
    func treeRefusal(_ files: ScannedFiles) -> String? {
        let unchanged = switch files {
        case .scanned(let current):
            current == scanned

        case .package(let root):
            scanned.allSatisfy { path, hash in
                ContentHash.sha256(ofFileAt: root.appendingPathComponent(path)) == hash
            }
        }
        return unchanged ? nil : Self.treeChangedReason
    }

    /// Writes the record to `directory`, replacing any there.
    func write(in directory: MutationDirectory) throws(MutationFailure) {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes]
        do {
            try encoder.encode(self).write(to: directory.pending, options: .atomic)
        } catch {
            throw MutationWorkCopy.failure("write .swiftstats/mutation/\(MutationDirectory.pendingName)", error)
        }
    }
}
