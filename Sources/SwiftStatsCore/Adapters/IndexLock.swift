//
//  IndexLock.swift
//  SwiftStatsCore
//
//  The T1 group's lock (M7, design §1.2): an exclusive, non-blocking
//  `flock` on `.swiftstats/index.lock`, outside the build directory so it
//  never meets SwiftPM's own lock. A second `scan --index` in the package
//  fails at once rather than waiting on SwiftPM. It is held from before
//  the build until the build's products have been read (its output, the
//  index store, outskirts), so a second scan can't empty the first's
//  standard-error file or rebuild the store under its readers; the system
//  drops it when the process ends, however it ends. Only `EWOULDBLOCK`
//  means another holder: a volume without `flock` support (`ENOTSUP`, or
//  `ENOLCK` on NFS without its lock daemon) is reported as the error it is,
//  never as another scan.
//

import Foundation

/// A held `index.lock`.
struct IndexLock: Sendable {
    /// The lock file's open descriptor, which holds the `flock`.
    private let descriptor: Int32

    /// Takes the lock on `file`, creating the file when missing; a failure
    /// when another process (or another open of the file in this one)
    /// holds it, the file can't be opened, or it can't be locked for
    /// another reason, which the failure names.
    init(file: URL) throws {
        let opened = open(file.path, O_CREAT | O_RDWR | O_CLOEXEC, S_IRUSR | S_IWUSR | S_IRGRP | S_IROTH)
        guard opened >= 0 else {
            throw CoverageFailure(description: "could not open .swiftstats/\(file.lastPathComponent)")
        }
        guard flock(opened, LOCK_EX | LOCK_NB) == 0 else {
            let code = errno
            close(opened)
            guard code == EWOULDBLOCK else {
                let reason = String(cString: strerror(code))
                throw CoverageFailure(description: "could not lock .swiftstats/\(file.lastPathComponent): \(reason)")
            }
            throw CoverageFailure(description: BuildSession.heldReason)
        }
        descriptor = opened
    }

    /// Releases the lock and closes its descriptor; called once.
    func release() {
        flock(descriptor, LOCK_UN)
        close(descriptor)
    }
}
