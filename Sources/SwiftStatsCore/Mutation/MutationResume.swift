//
//  MutationResume.swift
//  SwiftStatsCore
//
//  Where `scan --mutation --resume` starts (M6, design §1.7): the pending
//  run `pending.json` records, its kept copy in `work/`, and its results
//  file, named by the record (an interrupted scan names it too), or, for
//  a record that names none (a scan killed outright, or an older
//  SwiftStats), the one results file in SwiftMutator's log folder beside
//  the copy. A resume is refused, in this
//  order, when no run is pending, when it leaves other files out of the
//  tree than the run did, when the tree's git state differs from the run's,
//  when the settings differ, when a file the run's scan parsed changed,
//  was added or is gone, when the copy is gone, and when the results file
//  is missing or has no readable header (a run that stopped before its
//  first mutant). A run that ran and whose snapshot wasn't stored keeps no
//  copy: its resume needs only the results kept in `runs/<id>/`, which
//  must still read (design §6.4, as built). `scan` checks all of it
//  before anything runs, reading the files the run's scan parsed from the
//  package, and the mutation step again, under the package's mutation
//  lock, against the files its scan parsed, before it touches the copy or
//  the record. A `--since` run's
//  resume merges with the base its record names, which `scan` chooses
//  again (`MutationBase.resumed`); the step refuses it without that base.
//

import Foundation

/// A pending SwiftMutator run a resume can continue, with its copy and
/// its results file.
struct MutationResume {
    /// Why a resume is refused when the copy is gone.
    static let copyGoneReason = "the copy of that run is gone; run scan --mutation"
    /// Why it is refused when the results kept for a run whose snapshot
    /// wasn't stored are gone or no longer read.
    static let keptGoneReason = "the results that run kept are gone or don't read; run scan --mutation"
    /// Why it is refused when no results file can be continued.
    static let noResultsReason = "that run left no results a resume can continue; run scan --mutation"

    /// The run.
    let pending: PendingMutationRun
    /// Its kept copy, with the files it fixed when it was made.
    let copy: MutationWorkCopy
    /// Its results file.
    let resultsFile: URL

    /// Why `scan --mutation --resume` of the package at `root`, whose store
    /// path in the package is in `ignoring`, is refused under
    /// `configuration`, with tools found by `locator`; nil when it isn't.
    /// The settings are compared only when both tools are found: otherwise
    /// the scan skips the collector, saying why.
    static func refusal(
        root: URL,
        configuration: SwiftStatsConfiguration,
        locator: ToolLocator,
        ignoring: [String]
    ) -> String? {
        var settings: PendingMutationRun.Settings?
        if case let .found(mutator, swift) = MutationTools.resolve(
            root: root,
            configuration: configuration,
            locator: locator
        ) {
            settings = PendingMutationRun.Settings(
                mutator: mutator,
                swift: swift,
                settings: configuration.collectors[MutationAdapter.name]
            )
        }
        do {
            let git = GitReader.read(packageRoot: root, ignoring: ignoring)
            let files = PendingMutationRun.ScannedFiles.package(root)
            let record = try checked(root: root, git: git, ignoring: ignoring, files: files, settings: settings)
            if record.kept != nil {
                _ = try keptResults(of: record, root: root)
            } else {
                _ = try prepare(root: root, git: git, ignoring: ignoring, files: files, settings: settings)
            }
            return nil
        } catch {
            return error.description
        }
    }

    /// The run pending in the package at `root`, whose git state is `git`,
    /// read leaving out the files at `ignoring`, whose scanned files are
    /// now `files`, under `settings` (not compared when nil); a failure
    /// when there is none, or the tree or the settings refuse its resume.
    static func checked(
        root: URL,
        git: GitState,
        ignoring: [String],
        files: PendingMutationRun.ScannedFiles,
        settings: PendingMutationRun.Settings?
    ) throws(MutationFailure) -> PendingMutationRun {
        guard let record = try PendingMutationRun.read(in: MutationDirectory(lookingIn: root)) else {
            throw MutationFailure(description: PendingMutationRun.noneReason)
        }
        if let reason = record.refusal(git: git, ignoring: ignoring, settings: settings)
            ?? record.treeRefusal(files) {
            throw MutationFailure(description: reason)
        }
        return record
    }

    /// The results file `record`, of a run that ran in the package at
    /// `root` and whose snapshot wasn't stored, kept, with what it holds;
    /// a failure when it names none or they no longer read.
    static func keptResults(
        of record: PendingMutationRun,
        root: URL
    ) throws(MutationFailure) -> (file: URL, results: MutationResults) {
        guard let kept = record.kept else {
            throw MutationFailure(description: noResultsReason)
        }
        let file = root.appendingPathComponent(kept.resultsFile)
        guard case .results(let results) = MutationSession.read(file).1 else {
            throw MutationFailure(description: keptGoneReason)
        }
        return (file, results)
    }

    /// The resume of the run pending in the package at `root`, whose git
    /// state is `git`, read leaving out the files at `ignoring`, whose
    /// scanned files are now `files`, under `settings` (not compared when
    /// nil); a failure saying why it is refused.
    static func prepare(
        root: URL,
        git: GitState,
        ignoring: [String],
        files: PendingMutationRun.ScannedFiles,
        settings: PendingMutationRun.Settings?
    ) throws(MutationFailure) -> Self {
        let directory = MutationDirectory(lookingIn: root)
        let record = try checked(root: root, git: git, ignoring: ignoring, files: files, settings: settings)
        let work = directory.work
        let project = work.appendingPathComponent(record.project)
        guard FileClone.isDirectory(project) else {
            throw MutationFailure(description: copyGoneReason)
        }
        let named = record.resultsFile.map(work.appendingPathComponent)
        guard let file = named ?? MutationCommand.onlyResultsFile(in: MutationCommand.logFolder(of: project)),
              case .results = MutationSession.read(file).1 else {
            throw MutationFailure(description: noResultsReason)
        }
        return Self(
            pending: record,
            copy: MutationWorkCopy(work: work, project: project, fixedFiles: record.copyFixed),
            resultsFile: file
        )
    }

    /// `url`'s path relative to `work`, the copy's folder; nil when it
    /// isn't inside it.
    static func path(of url: URL, inside work: URL) -> String? {
        let base = work.standardizedFileURL.path + "/"
        let path = url.standardizedFileURL.path
        return path.hasPrefix(base) ? String(path.dropFirst(base.count)) : nil
    }
}
