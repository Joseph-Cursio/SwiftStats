//
//  MutationAdapter+Run.swift
//  SwiftStatsCore
//
//  A SwiftMutator run as the collector records it (M6, design §1.5 and
//  §1.8): the step's outcome becomes the status, whose version and
//  identity come from the results file's header, whose options add the
//  header's facts to the settings known before the run, and whose reason
//  joins the exit's own words with the notes a run that ran carries.
//

import Foundation

extension MutationAdapter {
    /// The note on results that don't list the mutants of code no test ran.
    static let notCoveredUnlistedNote = "results don't list mutants in code no test ran (a SwiftMutator build before "
        + "13f96a46), so genuinely under-tested is left out and functions no test ran aren't judged"

    /// Runs SwiftMutator as `job` says and records how it went.
    static func run(_ job: MutationJob) -> MutationRun {
        let known = options(settings: job.settings, root: job.root)
        let (result, milliseconds) = Stopwatch.time { () -> Result<MutationSession.Outcome, MutationFailure> in
            do throws(MutationFailure) {
                return .success(try MutationSession.run(job))
            } catch {
                return .failure(error)
            }
        }
        switch result {
        case .failure(let failure):
            return MutationRun(
                status: CollectorStatus(
                    name: name,
                    state: .failed,
                    version: nil,
                    reason: failure.description,
                    options: known
                ),
                executable: job.mutator,
                identity: nil,
                milliseconds: milliseconds,
                results: nil,
                suspects: .unjudged,
                resultsFile: nil,
                warmBuildMilliseconds: nil,
                mutatorMilliseconds: nil,
                warnings: []
            )

        case .success(let outcome):
            let notes = reasonNotes(outcome)
            return MutationRun(
                status: CollectorStatus(
                    name: name,
                    state: outcome.exit.state,
                    version: outcome.results?.facts.version,
                    reason: notes.isEmpty ? nil : notes.joined(separator: "; "),
                    options: known + (outcome.results.map { options(of: $0.facts) } ?? [])
                ),
                executable: job.mutator,
                identity: outcome.results.flatMap { identity(of: $0.facts) },
                milliseconds: milliseconds,
                results: outcome.exit.state == .ran ? outcome.results : nil,
                suspects: outcome.suspects,
                resultsFile: outcome.resultsFile,
                warmBuildMilliseconds: outcome.warmBuildMilliseconds,
                mutatorMilliseconds: outcome.mutatorMilliseconds,
                warnings: outcome.warnings
            )
        }
    }

    /// The parts of the reason of a run that ended as `outcome` says: the
    /// exit's words, then, for a run that ran, an incomplete file's reason,
    /// results that don't list code no test ran, failed control runs and
    /// files the copy fixed.
    static func reasonNotes(_ outcome: MutationSession.Outcome) -> [String] {
        var notes = [outcome.exit.reason].compactMap(\.self)
        guard outcome.exit.state == .ran else {
            return notes
        }
        if let results = outcome.results {
            notes += [results.incompleteReason].compactMap(\.self)
            if results.listsNotCovered == false {
                notes.append(notCoveredUnlistedNote)
            }
            if results.controlFailures > 0 {
                let runs = results.controlFailures == 1 ? "1 control run" : "\(results.controlFailures) control runs"
                notes.append("\(runs) failed (flaky tests)")
            }
        }
        if outcome.fixedFiles > 0 {
            let files = outcome.fixedFiles == 1 ? "1 file" : "\(outcome.fixedFiles) files"
            notes.append("copy fixed \(files) git checks out differently")
        }
        return notes
    }
}
