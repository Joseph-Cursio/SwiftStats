//
//  MutationLiveRun.swift
//  SwiftStatsCore
//
//  Whether a SwiftMutator run an earlier scan started is still running in
//  `.swiftstats/mutation/work/` (M6, design §1.2's lifecycle). SwiftMutator
//  never watches its parent, and each child leads a process group of its
//  own, so a scan killed without its cleanup (SIGKILL, a force quit)
//  leaves SwiftMutator and its tests running, and SwiftStats' own lock
//  goes with the scan. SwiftMutator holds an exclusive `flock` on
//  `<project>_mutated.lock` beside the project it runs in for the whole
//  run, which the kernel drops when it ends however it ends, and never
//  removes the file (`MutatedProjectLock` at b16642de). So before a step
//  discards or resumes what an earlier run left, it tries that lock
//  without waiting, on each project the leftover copy can hold (the one
//  this scan's copy would be, and the one `pending.json` names). A lock
//  that is held fails the step, leaving `work/` and `pending.json` alone:
//  removing `work/` would take the lock file with it, and the next run
//  would lock a new file while the earlier one still ran there.
//

import Foundation

/// Finds a SwiftMutator run still running in a package's leftover copy.
enum MutationLiveRun {
    /// Whether a lock file is held.
    enum Holder: Equatable {
        /// No process holds it.
        case free
        /// A process holds it: the one the file records, when it records one.
        case held(process: Int32?)
    }

    /// What follows a project's name in its SwiftMutator lock file's name.
    static let lockSuffix = "_mutated.lock"

    /// SwiftMutator's lock file for a run in `project`: beside it, named
    /// after it (`MutatedProjectNames.lockFile(of:)` at b16642de).
    static func lockFile(of project: URL) -> URL {
        project.deletingLastPathComponent().appendingPathComponent(project.lastPathComponent + lockSuffix)
    }

    /// Why the leftover copy in `directory`'s `work/` of the package at
    /// `packageRoot`, whose state is `git`, mustn't be touched: a
    /// SwiftMutator run holds its lock. Nil when there is no `work/`, or
    /// no run holds a lock in it.
    static func refusal(packageRoot: URL, git: GitState, in directory: MutationDirectory) -> MutationFailure? {
        guard FileClone.exists(directory.work) else {
            return nil
        }
        var projects = [MutationWorkCopy.projectPath(packageRoot: packageRoot, git: git)]
        if let pending = try? PendingMutationRun.read(in: directory), pending.project.isEmpty == false {
            projects.append(pending.project)
        }
        for project in projects {
            let lock = lockFile(of: directory.work.appendingPathComponent(project))
            if case .held(let process) = holder(of: lock) {
                let named = process.map { " (process \($0))" } ?? ""
                return MutationFailure(
                    description: "a SwiftMutator run an earlier scan started is still running in "
                        + ".swiftstats/mutation/work\(named); stop it, or wait for it to end, then scan again"
                )
            }
        }
        return nil
    }

    /// Whether the lock file at `lock` is held: tried with a non-blocking
    /// exclusive `flock`, released at once when it is free. A file that
    /// isn't there, or can't be opened or locked for another reason, is
    /// read as free: SwiftMutator makes the file before it runs anything.
    static func holder(of lock: URL) -> Holder {
        let descriptor = open(lock.path, O_RDONLY | O_CLOEXEC)
        guard descriptor >= 0 else {
            return .free
        }
        defer { close(descriptor) }
        guard flock(descriptor, LOCK_EX | LOCK_NB) != 0 else {
            flock(descriptor, LOCK_UN)
            return .free
        }
        guard errno == EWOULDBLOCK else {
            return .free
        }
        return .held(process: recordedProcess(in: lock))
    }

    /// The process identifier the holder records on the lock file's first
    /// line (`<pid> <start>`); nil when it records none.
    private static func recordedProcess(in lock: URL) -> Int32? {
        guard let text = try? String(contentsOf: lock, encoding: .utf8),
              let field = text.split(separator: "\n").first?.split(separator: " ").first,
              let process = Int32(field), process > 0 else {
            return nil
        }
        return process
    }
}
