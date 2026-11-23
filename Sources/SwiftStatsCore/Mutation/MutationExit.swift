//
//  MutationExit.swift
//  SwiftStatsCore
//
//  How a SwiftMutator run ended, as the collector's state (M6, design §1.5,
//  U9), keyed on how the process ended and what it left: SwiftMutator ends
//  an interrupted run by raising the signal again, so an interrupt reads
//  as that signal, and `128 + n` is only its fallback. A results file that
//  doesn't read fails the run whatever the exit. Exit 0 and 2 with results
//  ran, and so does exit 0 without a results file for a `--since` run,
//  which had nothing left to test once its selection was filtered (design
//  §6.1); exit 255 with SwiftMutator's "nothing to test" line ran with no
//  results; everything else failed, with a reason that holds no path. A
//  failed run whose results file has a readable header can be resumed, so
//  its copy is kept.
//

import Foundation

/// The collector's state after a SwiftMutator run.
struct MutationExit: Equatable, Sendable {
    /// What the run left for SwiftStats to read.
    enum Output: Equatable, Sendable {
        /// No results file.
        case noFile
        /// Only a `stopped` line: it stopped before its first mutant.
        case stopped(MutationStop)
        /// Results, from at least one readable session.
        case results(MutationResults)
        /// A results file that doesn't read, and why.
        case unreadable(MutationFailure)
    }

    /// The first line of SwiftMutator's error when it found no code to
    /// mutate (`MuterError.noMutationPointsDiscovered` and
    /// `.noSourceFilesDiscovered` at b16642de), which exits 255.
    static let nothingToTestLine = "SwiftMutator wasn't able to discover any code it could mutation test."
    /// The reason when it found nothing to test.
    static let nothingToTestReason = "nothing SwiftMutator could test"
    /// How a resumable failure ends its reason.
    static let resumeHint = "scan --mutation --resume continues it"
    /// What a baseline failure advises.
    static let baselineAdvice =
        "SwiftMutator needs passing tests; collectors.swiftmutator.arguments can --skip them"
    /// The most failing tests a baseline failure names.
    static let listedFailedTests = 5
    /// The exit status of an abort mid-run, whose results are kept.
    static let abortedStatus: Int32 = 4
    /// The exit status SwiftMutator uses for any other error.
    static let otherErrorStatus: Int32 = 255
    /// The exit status of a run that tested and found every mutant a
    /// build error.
    static let allBuildErrorsStatus: Int32 = 2
    /// The exit status of a failed baseline: nothing was tested.
    static let baselineStatus: Int32 = 3
    /// The exit status when SwiftMutator refuses a resume, of a tree or
    /// settings changed since the run started.
    static let resumeRefusedStatus: Int32 = 5
    /// The exit status when another SwiftMutator run holds its lock.
    static let lockedStatus: Int32 = 6
    /// What a shell adds to a signal's number when a process exits as if
    /// the signal had ended it.
    static let signalBase: Int32 = 128
    /// The signals SwiftMutator stops cleanly on, which it falls back to
    /// reporting as `128 + n` when raising them again fails.
    static let stoppingSignals: Set<Int32> = [SIGHUP, SIGINT, SIGTERM]
    /// The names of the signals a reason names, by number.
    private static let signalNames: [Int32: String] = [
        SIGHUP: "SIGHUP", SIGINT: "SIGINT", SIGQUIT: "SIGQUIT", SIGABRT: "SIGABRT", SIGKILL: "SIGKILL",
        SIGBUS: "SIGBUS", SIGSEGV: "SIGSEGV", SIGTERM: "SIGTERM"
    ]

    /// `ran` or `failed`.
    let state: CollectorState
    /// Why it failed, or the exit's own note on a run that ran; nil when
    /// there is nothing to say.
    let reason: String?
    /// Whether the run can be resumed, so its copy is kept.
    let resumable: Bool

    /// The name of signal `number` (`SIGTERM`), or `signal <n>`.
    static func signalName(_ number: Int32) -> String {
        signalNames[number] ?? "signal \(number)"
    }

    /// The state after a run that ended by `termination`, left `output`,
    /// and printed `log`, of which `tail` is the last lines, cleaned; a
    /// `--since` run (`since`) that exits 0 without a results file ran.
    static func judge(
        _ termination: ProcessTermination,
        output: Output,
        log: String,
        tail: String,
        since: Bool
    ) -> Self {
        if case .unreadable(let failure) = output {
            return failed(failure.description)
        }
        switch termination {
        case .signalled(let number):
            return interrupted(by: number, output: output)

        case .exited(let status) where stoppingSignals.contains(status - signalBase):
            return interrupted(by: status - signalBase, output: output)

        case .exited(0) where since && output == .noFile:
            return Self(state: .ran, reason: nil, resumable: false)

        case .exited(let status):
            return exited(status, output: output, log: log, tail: tail)
        }
    }

    /// A failure for `reason`, not resumable.
    static func failed(_ reason: String) -> Self {
        Self(state: .failed, reason: reason, resumable: false)
    }

    /// `swift-mutator exited <status>`, followed by `tail` when it isn't
    /// empty.
    private static func exitedReason(_ status: Int32, tail: String) -> String {
        "swift-mutator exited \(status)" + (tail.isEmpty ? "" : ": \(tail)")
    }

    /// The state after an interruption by signal `number`: failed, and
    /// resumable when the results file has a readable header.
    private static func interrupted(by number: Int32, output: Output) -> Self {
        let canResume = if case .results = output { true } else { false }
        let words = "interrupted by \(signalName(number))" + (canResume ? "; \(resumeHint)" : "")
        return Self(state: .failed, reason: words, resumable: canResume)
    }

    /// The state after exit `status`.
    private static func exited(_ status: Int32, output: Output, log: String, tail: String) -> Self {
        switch status {
        case 0, allBuildErrorsStatus:
            guard case .results = output else {
                if case .stopped(let stop) = output {
                    return failed(stopped(stop))
                }
                return failed("swift-mutator exited \(status) without a results file")
            }
            let note = status == allBuildErrorsStatus ? "every mutant was a build error" : nil
            return Self(state: .ran, reason: note, resumable: false)

        case baselineStatus:
            guard case .stopped(let stop) = output else {
                return failed(exitedReason(status, tail: tail))
            }
            return failed(stopped(stop))

        case abortedStatus:
            return aborted(output)

        case lockedStatus:
            return failed("another SwiftMutator run holds its lock")

        case otherErrorStatus where log.contains(nothingToTestLine):
            return Self(state: .ran, reason: nothingToTestReason, resumable: false)

        default:
            return failed(exitedReason(status, tail: tail))
        }
    }

    /// The state after an abort mid-run: failed, with the end line's
    /// detail, and resumable when the results file has a readable header.
    private static func aborted(_ output: Output) -> Self {
        guard case .results(let results) = output else {
            if case .stopped(let stop) = output {
                return failed(stopped(stop))
            }
            return failed("aborted, leaving no results file")
        }
        let detail = results.end?.detail.map { ": \($0)" } ?? ""
        return Self(state: .failed, reason: "aborted\(detail); \(resumeHint)", resumable: true)
    }

    /// The reason a run that stopped before its first mutant gives: the
    /// step and why, up to five failing tests, and what to do.
    private static func stopped(_ stop: MutationStop) -> String {
        let how = switch stop.reason {
        case "timedOut":
            "timed out"

        case "interrupted":
            "was interrupted"

        default:
            "failed"
        }
        var words = "the \(stop.step) \(how)" + (stop.detail.map { " (\($0))" } ?? "")
        if stop.failedTests.isEmpty == false {
            let total = max(stop.failedTestCount ?? stop.failedTests.count, stop.failedTests.count)
            let listed = stop.failedTests.prefix(listedFailedTests)
            let more = total - listed.count
            words += "; failing: " + listed.joined(separator: ", ") + (more > 0 ? " and \(more) more" : "")
        }
        return words + "; " + baselineAdvice
    }

    /// The same state, resumable: a failed resume leaves the file it
    /// continued as it was, so it can still be resumed. When `hinting`,
    /// the reason ends with the resume hint, unless it already does.
    func keepingCopy(hinting: Bool) -> Self {
        let hint = "; \(Self.resumeHint)"
        guard hinting, let reason, reason.hasSuffix(hint) == false else {
            return Self(state: state, reason: reason, resumable: true)
        }
        return Self(state: state, reason: reason + hint, resumable: true)
    }
}
