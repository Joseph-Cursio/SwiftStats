//
//  FailedBuildLog.swift
//  SwiftStatsCore
//
//  Where a scan records the task log of a T1 build it ran that failed
//  (M7, design §1.5), so `scan` names
//  `.swiftstats/index-build/swiftstats-build.log` as M6 names SwiftMutator's
//  log: whether or not the scan then stored a snapshot, since a scan can
//  still throw after the build (M6's gate refusing held coverage before
//  SwiftMutator, a save refusing held results), leaving no report to read
//  the build's state from. Only a log this scan's own build command wrote
//  is recorded, never one another scan holding `index.lock` is writing, nor
//  one an earlier scan left: the scan records the log `BuildRun` carries,
//  which is set only once the build command has run.
//

import Foundation

/// The task log of the T1 build a scan ran, when that build failed.
public final class FailedBuildLog: @unchecked Sendable {
    /// Guards `log`.
    private let lock = NSLock()
    /// The log, once recorded.
    private var log: URL?

    /// The log of the failed build, when the scan recorded one; nil when
    /// the scan's build ran and succeeded, didn't run its command (skipped,
    /// refused by another scan's lock, failed before building), or the
    /// scan didn't ask for it.
    public var url: URL? {
        lock.lock()
        defer { lock.unlock() }
        return log
    }

    /// The line `scan` prints on standard error naming the log; nil when
    /// none was recorded.
    public var line: String? {
        url.map { "The index build's output is in \($0.path)" }
    }

    /// A record holding no log yet.
    public init() {
        // Nothing recorded until a scan's build fails.
    }

    /// Records `run`'s task log when the run failed after its build
    /// command ran; nothing otherwise.
    func record(_ run: BuildRun) {
        guard run.status.state == .failed, let written = run.log else {
            return
        }
        lock.lock()
        log = written
        lock.unlock()
    }

    deinit {
        // Nothing to release: the lock frees itself.
    }
}
