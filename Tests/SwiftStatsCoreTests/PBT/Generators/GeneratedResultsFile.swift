//
//  GeneratedResultsFile.swift
//  SwiftStatsCoreTests
//
//  A generated results.jsonl, the input of P3.4 to P3.6: its draft, and its
//  bytes, rendered when asked for (a property asks once per run; the
//  generator's meta-tests never do). A failure report shows each physical line, in
//  ASCII (`PBTTrace.ascii`), with what the model says the reader makes of
//  it, and how the lines break.
//

import Foundation
import Testing

/// A generated results file.
struct GeneratedResultsFile: Sendable, CustomTestStringConvertible {
    /// The hex digits a byte is shown in.
    static let hexadecimal = 16

    /// The file as decisions.
    let draft: ResultsFileDraft

    /// Its bytes.
    var data: Data {
        draft.data
    }

    /// The physical lines, numbered, each with its model label, then the
    /// outcome the model expects, in ASCII.
    var testDescription: String {
        let expected = ResultsFileModel.expected(of: draft)
        let breaks = (draft.crlf ? "CRLF" : "LF") + (draft.finalBreak ? "" : ", no final line break")
        let lines = data.split(separator: ResultsLineRenderer.lineFeed, omittingEmptySubsequences: false)
        let numbered = lines.prefix(draft.lines.count).enumerated().map { index, bytes in
            let label = index < expected.labels.count ? "\(expected.labels[index])" : "refusing"
            return "\(index + 1) [\(label)]: " + Self.shown(bytes)
        }
        return PBTTrace.ascii(
            "\(draft.lines.count) lines, \(breaks), expected " + expected.outcome.testDescription + "\n"
                + numbered.joined(separator: "\n")
        )
    }

    /// `bytes` as a Swift string literal, or, when they aren't UTF-8, as
    /// their hex values.
    static func shown(_ bytes: some Collection<UInt8>) -> String {
        guard let text = String(bytes: bytes, encoding: .utf8) else {
            return "bytes " + bytes.map { String($0, radix: hexadecimal) }.joined(separator: " ")
        }
        return text.debugDescription
    }
}
