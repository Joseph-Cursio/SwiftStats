//
//  GeneratedBuildLine.swift
//  SwiftStatsCoreTests
//
//  One line of a generated build-output file, as written and as it should
//  read: its kind, its text once escapes are stripped, its bytes with the
//  escapes, its line break, its label and its traits.
//

import Foundation

/// A generated build-output line, written and labelled.
struct GeneratedBuildLine: Hashable, Sendable {
    /// The kind of line.
    let shape: BuildLineShape
    /// What the line reads as once escapes are stripped.
    let text: String
    /// The bytes written, escapes included, line break excluded.
    let written: [UInt8]
    /// The line break after it: LF, CRLF, or nothing for an unterminated
    /// last line.
    let lineBreak: String
    /// What the line should read as.
    let reading: BuildLineReading
    /// What the line has besides its kind.
    let traits: Set<BuildLineTrait>

    /// The line's bytes, its line break included.
    var data: Data {
        Data(written + Array(lineBreak.utf8))
    }

    /// The line as written, escapes and line break shown as Swift escapes,
    /// and its label: `"…\n" -> entry(…)`.
    var testDescription: String {
        let decoded = String(bytes: written, encoding: .utf8) ?? String(bytes: written, encoding: .isoLatin1) ?? ""
        let shown = decoded + lineBreak
        return "\(shown.debugDescription) -> \(reading)"
    }
}
