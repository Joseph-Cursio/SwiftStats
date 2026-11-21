//
//  CoverageStderr.swift
//  SwiftStatsCore
//
//  A failed coverage command's standard error, cut down to a reason (M5): a
//  failed compile prints the whole multi-kilobyte driver command line,
//  which would push the located error out of the last lines kept.
//

import Foundation

/// Turns a failed command's standard error into a bounded reason.
enum CoverageStderr {
    /// How many lines the reason keeps, the last ones.
    static let keptLines = 20
    /// How many characters of a line the reason keeps.
    static let lineLimit = 300
    /// An indented line longer than this is a command line, dropped.
    static let commandLineLength = 1_000
    /// What a cut line ends with.
    private static let ellipsis = "…"
    /// What a header followed by an indented command line contains.
    private static let commandLineHeader = "Command line:"

    /// `text`, cleaned: the indented lines after an `error: … Command line:`
    /// header, the rest of the header's own line, and any indented line over
    /// `commandLineLength` characters are dropped; each directory in `replacements` is redacted, however it is
    /// spelled; each line is trimmed and cut at `lineLimit` characters;
    /// blank lines are dropped and the last `keptLines` are kept.
    static func cleaned(_ text: String, replacing replacements: [(URL, String)]) -> String {
        var lines: [String] = []
        var inCommandLine = false
        for line in text.split(whereSeparator: \.isNewline).map(String.init) {
            let indented = line.first?.isWhitespace == true
            if indented, inCommandLine || line.count > commandLineLength {
                continue
            }
            // The command line starts on the header's own line.
            let header = line.hasPrefix("error:") ? line.range(of: commandLineHeader) : nil
            inCommandLine = header != nil
            let kept = header.map { String(line[..<$0.upperBound]) } ?? line
            let redacted = SwiftInferTargetRun.redacted(kept, replacing: replacements)
                .trimmingCharacters(in: .whitespaces)
            guard redacted.isEmpty == false else {
                continue
            }
            lines.append(redacted.count > lineLimit ? String(redacted.prefix(lineLimit)) + ellipsis : redacted)
        }
        return lines.suffix(keptLines).joined(separator: "\n")
    }
}
