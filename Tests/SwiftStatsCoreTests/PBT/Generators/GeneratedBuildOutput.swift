//
//  GeneratedBuildOutput.swift
//  SwiftStatsCoreTests
//
//  A generated build's standard error and task log, each line written and
//  labelled with what it should read as, and what the whole should read as:
//  the input of the build-output properties (one input struct per property,
//  design D7). The entries, the unparsed timing lines and the escaped lines
//  are always stated; the diagnostics and the other warnings are stated
//  only when no wild line is present (`expected`), since a wild line may
//  read as a diagnostic or a warning. A test report shows every line as
//  written, escapes and line breaks visible, with its label.
//

import Foundation
@testable import SwiftStatsCore
import Testing

/// A generated build's two output files, written and labelled.
struct GeneratedBuildOutput: Sendable, CustomTestStringConvertible {
    /// The rules the labels follow and the shapes were limited to.
    let rules: BuildOutputGen.Rules
    /// The standard error's lines.
    let stderrLines: [GeneratedBuildLine]
    /// The task log's lines.
    let logLines: [GeneratedBuildLine]

    /// The standard error's bytes.
    var stderr: Data {
        Data(stderrLines.flatMap(\.data))
    }

    /// The task log's bytes.
    var log: Data {
        Data(logLines.flatMap(\.data))
    }

    /// Both files' lines, standard error first.
    var lines: [GeneratedBuildLine] {
        stderrLines + logLines
    }

    /// Every trait any line has.
    var traits: Set<BuildLineTrait> {
        lines.reduce(into: []) { $0.formUnion($1.traits) }
    }

    /// The timing entries the standard error should read as, in order.
    var entries: [TimingEntry] {
        stderrLines.compactMap { line in
            if case .entry(let entry) = line.reading {
                return entry
            }
            return nil
        }
    }

    /// How many standard error lines should be counted as holding
    /// `ms<TAB>` but stating no entry.
    var unparsedTimingLines: Int {
        stderrLines.count { $0.reading == .unparsedTiming }
    }

    /// How many lines of either file hold an escape sequence.
    var escapedLines: Int {
        lines.count { $0.traits.contains(.escaped) }
    }

    /// Whether every line's reading is stated: no wild line is present.
    var isFullyStated: Bool {
        lines.allSatisfy { $0.reading != .unstated }
    }

    /// What the reader should return, when every line's reading is stated:
    /// the diagnostics of both files kept once each, standard error first,
    /// in the order first seen; nil when a wild line is present.
    var expected: BuildOutput? {
        guard isFullyStated else {
            return nil
        }
        var seen = Set<BuildDiagnostic>()
        let diagnostics = lines.reduce(into: [BuildDiagnostic]()) { kept, line in
            if case .diagnostic(let diagnostic) = line.reading, seen.insert(diagnostic).inserted {
                kept.append(diagnostic)
            }
        }
        return BuildOutput(
            entries: entries,
            diagnostics: diagnostics,
            escapedLines: escapedLines,
            unparsedTimingLines: unparsedTimingLines,
            otherWarningLines: lines.count { $0.reading == .otherWarning }
        )
    }

    /// Both files, line by line, as written and labelled.
    var testDescription: String {
        let stderrText = stderrLines.map { "  " + $0.testDescription }
        let logText = logLines.map { "  " + $0.testDescription }
        return (["stderr (\(rules)):"] + stderrText + ["log:"] + logText).joined(separator: "\n")
    }

    /// The output `stderr` and `log` hold, written and labelled under
    /// `rules`.
    init(rules: BuildOutputGen.Rules, stderr: BuildFileDraft, log: BuildFileDraft) {
        self.rules = rules
        stderrLines = BuildOutputInterpreter.lines(of: stderr, rules: rules, timings: true)
        logLines = BuildOutputInterpreter.lines(of: log, rules: rules, timings: false)
    }
}
