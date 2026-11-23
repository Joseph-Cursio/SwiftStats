//
//  MutationSession+Interrupted.swift
//  SwiftStatsCore
//
//  What an interruption leaves of `pending.json` (M6, design §1.7, as
//  built). An interrupted scan stops SwiftMutator and then ends by the
//  signal, so the step never learns how the run ended and can't name its
//  results file. The run is therefore started with work the interruption
//  does once it has stopped SwiftMutator, before the scan ends
//  (`ScratchRegistry`): it finds the results file as a run's end does, the
//  one file in the one run folder of SwiftMutator's log folder beside the
//  copy, and rewrites the record naming it when it has a readable header,
//  so a resume continues that file however many run folders the log folder
//  holds by then; otherwise, when there is no file, more than one, or one
//  with no header (a run stopped before its first mutant, which leaves at
//  most a `stopped` line), it removes the record, since no resume could
//  continue the run, and the next run recovers the copy.
//

import Foundation

extension MutationSession {
    /// Rewrites `pending`, the record of a run stopped by an interruption
    /// in the project `project` inside `work`, in `folder`, naming the
    /// results file the run left when it has a readable header; removes
    /// the record otherwise.
    static func recordInterrupted(
        _ pending: PendingMutationRun,
        project: URL,
        work: URL,
        in folder: MutationDirectory
    ) {
        if let file = MutationCommand.onlyResultsFile(in: MutationCommand.logFolder(of: project)),
           case .results = read(file).1,
           let path = MutationResume.path(of: file, inside: work) {
            try? pending.naming(resultsFile: path).write(in: folder)
        } else {
            try? PendingMutationRun.remove(in: folder)
        }
    }

    /// The work an interruption does once it has stopped SwiftMutator's
    /// run, which `pending` records, in `copy`: naming the run's results
    /// file in the record when it has a readable header, else removing the
    /// record. Failures are ignored: the scan is ending.
    func afterInterruption(of pending: PendingMutationRun, in copy: MutationWorkCopy) -> @Sendable () -> Void {
        let folder = directory
        let project = copy.project
        let work = copy.work
        return {
            Self.recordInterrupted(pending, project: project, work: work, in: folder)
        }
    }
}
