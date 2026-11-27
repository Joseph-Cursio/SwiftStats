//
//  BuildOutputReader.swift
//  SwiftStatsCore
//
//  Reads the T1 build's output (M7, design §6.1): its standard error, which
//  holds the type-check timing lines and the diagnostics, and its standard
//  output, the `-v` task log, read only for diagnostics. Each line loses
//  its ANSI and OSC-8 escapes first (`BuildLineEscapes`, counted), then is
//  read by `BuildLineGrammar`, first that matches: a timing line (standard
//  error only; one holding `ms<TAB>` that doesn't read is counted); a
//  source excerpt, box or decorated line, which is skipped; a diagnostic's
//  first line. A diagnostic's message takes the lines after it that can't
//  be anything else (a line holding `ms<TAB>` is never one, so a refused
//  timing line ends the message, and on the standard error is counted), at
//  most 20, up to the last of them after which the joined text ends with
//  an ID or a group (all of them when none does), which are read from that
//  end (`DiagnosticText`), so a quoted source line ending ` [word]` doesn't
//  end it early; a macro diagnostic's place is the origin note on the line
//  after its message. A line starting `warning: ` that is none of these
//  (Swift Build's summary form, a manifest command `-v` prints as a
//  warning, SwiftPM's own package warnings) is counted; every other line
//  is ignored. The two files' diagnostics are kept once each, standard
//  error first.
//

import Foundation

/// Reads the T1 build's standard error and task log.
enum BuildOutputReader {
    /// What one file's lines hold.
    private struct FileLines {
        /// The timing entries, in order.
        var entries: [TimingEntry] = []
        /// The diagnostics, in order, duplicates included.
        var diagnostics: [BuildDiagnostic] = []
        /// Lines that held an escape sequence.
        var escaped = 0
        /// Lines holding `ms<TAB>` that state no entry.
        var unparsed = 0
        /// Lines starting `warning: ` that aren't diagnostics.
        var otherWarnings = 0
    }

    /// How many lines can continue a diagnostic's message.
    static let continuationLimit = 20
    /// What a line Swift Build prints as a warning but isn't a diagnostic
    /// starts with, as scalars: a combining mark after its space doesn't
    /// hide it (decided U13).
    static let warningPrefix = "warning: ".unicodeScalars
    /// The UTF-8 newline byte.
    private static let newline = UInt8(ascii: "\n")
    /// The UTF-8 carriage return byte.
    private static let carriageReturn = UInt8(ascii: "\r")

    /// The output of a build whose standard error is `stderr` and whose
    /// standard output is `log`.
    static func read(stderr: Data, log: Data) -> BuildOutput {
        let errors = read(lines(of: stderr), timings: true)
        let tasks = read(lines(of: log), timings: false)
        var seen = Set<BuildDiagnostic>()
        let diagnostics = (errors.diagnostics + tasks.diagnostics).filter { seen.insert($0).inserted }
        return BuildOutput(
            entries: errors.entries,
            diagnostics: diagnostics,
            escapedLines: errors.escaped + tasks.escaped,
            unparsedTimingLines: errors.unparsed,
            otherWarningLines: errors.otherWarnings + tasks.otherWarnings
        )
    }

    /// The lines of `data`, a final newline ending the last one, each
    /// without a trailing carriage return; a line that isn't UTF-8 is read
    /// as Latin-1.
    private static func lines(of data: Data) -> [String] {
        var lines = data.split(separator: newline, omittingEmptySubsequences: false)
        if lines.last?.isEmpty == true {
            lines.removeLast()
        }
        return lines.map { line in
            let bytes = line.last == carriageReturn ? line.dropLast() : line
            return String(bytes: bytes, encoding: .utf8) ?? String(bytes: bytes, encoding: .isoLatin1) ?? ""
        }
    }

    /// What `raw` holds, its timing lines read when `timings`.
    private static func read(_ raw: [String], timings: Bool) -> FileLines {
        var file = FileLines()
        let lines = raw.map { line in
            let stripped = BuildLineEscapes.strip(line)
            if stripped.escaped {
                file.escaped += 1
            }
            return stripped.text
        }
        var index = 0
        while index < lines.count {
            let text = lines[index]
            index += 1
            if timings, BuildLineGrammar.holdsTimingMark(text) {
                if let entry = BuildLineGrammar.timingEntry(text) {
                    file.entries.append(entry)
                    continue
                }
                file.unparsed += 1
            }
            if BuildLineGrammar.isStructural(text) {
                continue
            }
            if let header = BuildLineGrammar.header(text[...]) {
                let read = diagnostic(header, following: lines[index...])
                file.diagnostics.append(read.diagnostic)
                index += read.consumed
                continue
            }
            if BuildLineGrammar.starts(text, with: warningPrefix) {
                file.otherWarnings += 1
            }
        }
        return file
    }

    /// The diagnostic `header` begins, and how many of the `following`
    /// lines its message's continuation took (the origin note after a
    /// macro diagnostic is read, not taken).
    private static func diagnostic(
        _ header: DiagnosticHeader,
        following: ArraySlice<String>
    ) -> (diagnostic: BuildDiagnostic, consumed: Int) {
        var joined = String(header.message)
        var consumed = 0
        // The message ends at the last line, of those that can continue it,
        // after which the joined text ends with an ID or a group: a quoted
        // source line ending ` [word]` reads as one, but the real suffix
        // comes on a later line.
        var complete = DiagnosticText(joined).isComplete ? (text: joined, consumed: 0) : nil
        for line in following.prefix(continuationLimit) {
            guard BuildLineGrammar.continues(line) else {
                break
            }
            joined += "\n" + line
            consumed += 1
            if DiagnosticText(joined).isComplete {
                complete = (joined, consumed)
            }
        }
        if let complete {
            joined = complete.text
            consumed = complete.consumed
        }
        var origin: BuildPlace?
        if case .macro = header.location, let next = following.dropFirst(consumed).first {
            origin = BuildLineGrammar.originPlace(next)
        }
        let text = DiagnosticText(joined)
        let diagnostic = BuildDiagnostic(
            severity: header.severity,
            location: header.location,
            message: text.message,
            identifier: text.identifier,
            group: text.group,
            origin: origin
        )
        return (diagnostic, consumed)
    }
}
