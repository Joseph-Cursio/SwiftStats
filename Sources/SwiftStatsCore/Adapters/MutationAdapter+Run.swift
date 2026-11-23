//
//  MutationAdapter+Run.swift
//  SwiftStatsCore
//
//  A SwiftMutator run as the collector records it (M6, design §1.5 and
//  §1.8): the step's outcome becomes the status, whose version and
//  identity come from the results file's header, whose options add the
//  header's facts to the settings known before the run (and, for a run
//  that ran, the rule its mutants are mapped by), and whose reason
//  joins the exit's own words with the notes a run that ran carries.
//

import Foundation

extension MutationAdapter {
    /// The note on results that don't list the mutants of code no test ran.
    static let notCoveredUnlistedNote = "results don't list mutants in code no test ran (a SwiftMutator build before "
        + "13f96a46), so genuinely under-tested is left out and functions no test ran aren't judged"

    /// The last option of a run that ran: the rule its mutants are mapped
    /// by, which a carry checks.
    static let mapOption = "map: " + MutationMapper.rule

    /// Runs SwiftMutator as `job` says and records how it went. A
    /// `--since` run that ran without a results file reports the base's
    /// build, version and header options, since it ran that build with
    /// those settings and every result it holds comes from the base.
    static func run(_ job: MutationJob) -> MutationRun {
        let known = options(settings: job.settings, root: job.root)
        let startedAt = Date().formatted(PendingMutationRun.dateFormat)
        let (result, milliseconds) = Stopwatch.time { () -> Result<MutationSession.Outcome, MutationFailure> in
            do throws(MutationFailure) {
                return .success(try MutationSession.run(job))
            } catch {
                return .failure(error)
            }
        }
        switch result {
        case .failure(let failure):
            return failed(failure, job: job, options: known, milliseconds: milliseconds, startedAt: startedAt)

        case .success(let outcome):
            let ran = outcome.exit.state == .ran
            let notes = reasonNotes(outcome)
            let base = ran ? job.base : nil
            let header = outcome.results.map { options(of: $0.facts) } ?? base?.recordedHeaderOptions ?? []
            return MutationRun(
                status: CollectorStatus(
                    name: name,
                    state: outcome.exit.state,
                    version: outcome.results?.facts.version ?? base?.version,
                    reason: notes.isEmpty ? nil : notes.joined(separator: "; "),
                    options: known + header + (ran ? [mapOption] : [])
                ),
                executable: job.mutator,
                identity: outcome.results.flatMap { identity(of: $0.facts) } ?? base?.identity,
                milliseconds: milliseconds,
                results: ran ? outcome.results : nil,
                suspects: outcome.suspects,
                git: job.git,
                resultsFile: outcome.resultsFile,
                warmBuildMilliseconds: outcome.warmBuildMilliseconds,
                mutatorMilliseconds: outcome.mutatorMilliseconds,
                warnings: outcome.warnings,
                base: job.base,
                changes: outcome.changes,
                exitReason: outcome.exit.reason,
                fixedFiles: outcome.fixedFiles,
                startedAt: startedAt
            )
        }
    }

    /// The run of `job`, started at `startedAt`, that failed with
    /// `failure` after `milliseconds`, its settings giving `options`.
    static func failed(
        _ failure: MutationFailure,
        job: MutationJob,
        options: [String],
        milliseconds: Int,
        startedAt: String
    ) -> MutationRun {
        MutationRun(
            status: CollectorStatus(
                name: name,
                state: .failed,
                version: nil,
                reason: failure.description,
                options: options
            ),
            executable: job.mutator,
            identity: nil,
            milliseconds: milliseconds,
            results: nil,
            suspects: .unjudged,
            git: job.git,
            resultsFile: nil,
            warmBuildMilliseconds: nil,
            mutatorMilliseconds: nil,
            warnings: [],
            base: job.base,
            changes: nil,
            exitReason: failure.description,
            fixedFiles: 0,
            startedAt: startedAt
        )
    }

    /// The parts of the reason of a run that ended as `outcome` says: the
    /// exit's words, then, for a run that ran, an incomplete file's reason,
    /// results that don't list code no test ran, failed control runs and
    /// files the copy fixed.
    static func reasonNotes(_ outcome: MutationSession.Outcome) -> [String] {
        reasonNotes(
            exit: outcome.exit,
            results: outcome.results,
            listsNotCovered: outcome.results?.listsNotCovered ?? true,
            merge: [],
            fixedFiles: outcome.fixedFiles
        )
    }

    /// The parts of the reason of a run that ended as `exit` says, with
    /// `results` (nil when it left none): the exit's words, then, for a run
    /// that ran, a merge's `merge` notes, an incomplete file's reason,
    /// results that don't list code no test ran (`listsNotCovered` false),
    /// failed control runs, and `fixedFiles`, the files the copy fixed.
    static func reasonNotes(
        exit: MutationExit,
        results: MutationResults?,
        listsNotCovered: Bool,
        merge: [String],
        fixedFiles: Int
    ) -> [String] {
        var notes = [exit.reason].compactMap(\.self)
        guard exit.state == .ran else {
            return notes
        }
        notes += merge
        notes += [results?.incompleteReason].compactMap(\.self)
        if listsNotCovered == false {
            notes.append(notCoveredUnlistedNote)
        }
        if let failures = results?.controlFailures, failures > 0 {
            let runs = failures == 1 ? "1 control run" : "\(failures) control runs"
            notes.append("\(runs) failed (flaky tests)")
        }
        if fixedFiles > 0 {
            let files = fixedFiles == 1 ? "1 file" : "\(fixedFiles) files"
            notes.append("copy fixed \(files) git checks out differently")
        }
        return notes
    }
}
