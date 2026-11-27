//
//  AntecedentTally.swift
//  SwiftStatsCoreTests
//
//  How often each antecedent of a conditional law fired during a property
//  test ("when the key collides", "when the carry is refused"). A law whose
//  antecedent never fires checks nothing, so a property fires its labels in
//  the body, reports the tally after `propertyCheck`, and requires each
//  label to have fired at least once, with the run count chosen so that a
//  label with chance p per run stays silent with probability below 10⁻⁶.
//  Exact floors live in the generators' deterministic meta-tests, never
//  here, so a random run can't fail on bad luck. A check that fails stops
//  at its first failing input, so its tally covers only the runs before
//  it: a property passes its `FirstFailureLatch`, and once the latch is
//  claimed nothing is required, so the failure's report holds the law's
//  issue and the engine's seed and no antecedent noise. A class behind an
//  `NSLock`, safe for the engine's parallel runs; `Mutex` needs macOS 15.
//

import Foundation
import Testing

/// The number of times each antecedent label fired.
final class AntecedentTally: @unchecked Sendable { // every `var` is behind `lock`
    /// Guards `counts`.
    private let lock = NSLock()
    /// How often each label fired; a label that never fired is absent.
    private var counts: [String: Int] = [:]

    /// Each label and its count, in label order, one `label: count` pair per
    /// label, joined by commas; `nothing fired` when no label fired.
    var summary: String {
        let pairs = lock.withLock { counts.sorted { $0.key < $1.key } }
        guard pairs.isEmpty == false else {
            return "nothing fired"
        }
        return pairs.map { "\($0.key): \($0.value)" }.joined(separator: ", ")
    }

    /// Counts one firing of `label`.
    func fire(_ label: String) {
        lock.withLock { counts[label, default: 0] += 1 }
    }

    /// How often `label` has fired.
    func count(_ label: String) -> Int {
        lock.withLock { counts[label] ?? 0 }
    }

    /// Prints the summary to standard error, naming the running test.
    func report() {
        let name = Test.current.map { $0.displayName ?? $0.name } ?? "no test"
        FileHandle.standardError.write(Data("PBT antecedents [\(name)]: \(summary)\n".utf8))
    }

    /// Records an issue at `sourceLocation` for each of `labels` that never
    /// fired, naming it and the summary.
    func requireFired(_ labels: [String], sourceLocation: SourceLocation) {
        for label in labels where count(label) == 0 {
            Issue.record(
                "Antecedent \"\(label)\" never fired, so its law checked nothing (\(summary))",
                sourceLocation: sourceLocation
            )
        }
    }

    /// Records an issue at `sourceLocation` for each of `labels` that never
    /// fired, as `requireFired(_:sourceLocation:)` does, unless `latch` is
    /// claimed: its check failed, so the tally covers only the runs before
    /// the failure, and an antecedent that hadn't fired by then says
    /// nothing.
    func requireFired(_ labels: [String], unlessFailed latch: FirstFailureLatch, sourceLocation: SourceLocation) {
        guard latch.hasFailed == false else {
            return
        }
        requireFired(labels, sourceLocation: sourceLocation)
    }

    deinit {
        // Nothing to release.
    }
}
