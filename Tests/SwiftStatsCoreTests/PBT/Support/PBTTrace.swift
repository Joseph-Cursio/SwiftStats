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
//  Each line is ASCII, every other scalar written as a Swift escape
//  (`\u{E9}`): `swift test` relays a test's output in chunks, and a whole
//  first-failure line holding emoji and Arabic scalars never arrived
//  (step 6b's calibration), where the same line in ASCII did.
//

import Foundation
import Testing

/// The inputs property tests print: every one under tracing, and each
/// check's first failing one always.
enum PBTTrace {
    /// The environment variable that turns tracing on, when it is `1`.
    static let traceVariable = "SWIFTSTATS_PBT_TRACE"
    /// The radix a scalar past ASCII is written in.
    static let hexadecimal = 16

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

    /// The line `note(_:)` prints for `input` drawn in `test`, in ASCII.
    static func noteText(_ input: some Any, test: Test?) -> String {
        ascii("PBT trace [\(name(of: test))]: \(String(describingForTest: input))")
    }

    /// The line `firstFailure(_:latch:)` prints for `input` failing in
    /// `test`, in ASCII, or nil when `latch` shows its check has printed one
    /// already.
    static func firstFailureText(_ input: some Any, test: Test?, latch: FirstFailureLatch) -> String? {
        guard latch.claim() else {
            return nil
        }
        let description = String(describingForTest: input)
        return ascii("PBT first failing input, before shrinking [\(name(of: test))]: " + description)
    }

    /// `text` with every scalar past ASCII written as a Swift escape,
    /// `\u{` and its code point in uppercase hexadecimal, then `}`.
    static func ascii(_ text: String) -> String {
        text.unicodeScalars.map { scalar in
            scalar.isASCII ? String(scalar) : "\\u{" + String(scalar.value, radix: hexadecimal, uppercase: true) + "}"
        }
        .joined()
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
