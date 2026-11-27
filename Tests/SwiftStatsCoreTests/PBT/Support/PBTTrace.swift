//
//  PBTTrace.swift
//  SwiftStatsCoreTests
//
//  What a property test prints about its inputs, to standard error. The
//  engine reports a failure's seed only once shrinking ends, and replays
//  the first failing input with its issues suppressed; a time limit that
//  runs out while shrinking reports neither. So the first time a property's
//  check fails, `firstFailure(_:latch:)` prints that input, always, once per
//  check: the property makes a `FirstFailureLatch` outside `propertyCheck`.
//  And a subject that traps kills the process before the engine prints
//  anything, so under `SWIFTSTATS_PBT_TRACE=1` `note(_:)` prints every input
//  a property draws: run the one test with `--no-parallel`, and the last
//  line before the crash is the input. Tracing is a logging switch only.
//

import Foundation
import Testing

/// The inputs property tests print: every one under tracing, and each
/// check's first failing one always.
enum PBTTrace {
    /// The environment variable that turns tracing on, when it is `1`.
    static let traceVariable = "SWIFTSTATS_PBT_TRACE"

    /// Whether this process traces every input, read once.
    static let isTracing = isTracing(in: ProcessInfo.processInfo.environment)

    /// Whether `environment` turns tracing on: `SWIFTSTATS_PBT_TRACE` is `1`.
    static func isTracing(in environment: [String: String]) -> Bool {
        environment[traceVariable] == "1"
    }

    /// Prints `input` under tracing, naming the running test.
    static func note(_ input: some Any) {
        guard isTracing else {
            return
        }
        write(noteText(input, test: Test.current))
    }

    /// Prints `input` as the first failing input of the check `latch`
    /// belongs to, naming the running test, unless that check has printed
    /// one already.
    static func firstFailure(_ input: some Any, latch: FirstFailureLatch) {
        if let text = firstFailureText(input, test: Test.current, latch: latch) {
            write(text)
        }
    }

    /// The line `note(_:)` prints for `input` drawn in `test`.
    static func noteText(_ input: some Any, test: Test?) -> String {
        "PBT trace [\(name(of: test))]: \(String(describingForTest: input))"
    }

    /// The line `firstFailure(_:latch:)` prints for `input` failing in
    /// `test`, or nil when `latch` shows its check has printed one already.
    static func firstFailureText(_ input: some Any, test: Test?, latch: FirstFailureLatch) -> String? {
        guard latch.claim() else {
            return nil
        }
        return "PBT first failing input, before shrinking [\(name(of: test))]: "
            + String(describingForTest: input)
    }

    /// `test`'s display name, else its name, else a placeholder outside a test.
    private static func name(of test: Test?) -> String {
        test.map { $0.displayName ?? $0.name } ?? "no test"
    }

    /// Writes `text` and a line break to standard error.
    private static func write(_ text: String) {
        FileHandle.standardError.write(Data((text + "\n").utf8))
    }
}
