//
//  MutationLock.swift
//  SwiftStatsCore
//
//  The lock a mutation step holds (M6, design §1.2): an exclusive `flock`
//  on `.swiftstats/mutation/.lock`, taken before the copy is touched and
//  held until the step ends, so a second `scan --mutation` in the same
//  package fails at once rather than removing the first one's copy. The
//  system drops it when the process ends, however it ends.
//

import Foundation

/// Runs work while holding a package's mutation lock.
enum MutationLock {
    /// Why a step couldn't take the lock because another holds it.
    static let heldReason = "another scan --mutation is running in this package"

    /// `body`'s result, run while holding the lock at `file`; a failure,
    /// without running `body`, when another process (or another open of
    /// the file in this one) holds it or the file can't be opened.
    static func holding<Value>(
        _ file: URL,
        _ body: () throws(MutationFailure) -> Value
    ) throws(MutationFailure) -> Value {
        let descriptor = open(file.path, O_CREAT | O_RDWR | O_CLOEXEC, S_IRUSR | S_IWUSR | S_IRGRP | S_IROTH)
        guard descriptor >= 0 else {
            throw MutationFailure(description: "could not open .swiftstats/mutation/\(file.lastPathComponent)")
        }
        defer { close(descriptor) }
        guard flock(descriptor, LOCK_EX | LOCK_NB) == 0 else {
            throw MutationFailure(description: heldReason)
        }
        defer { flock(descriptor, LOCK_UN) }
        return try body()
    }
}
