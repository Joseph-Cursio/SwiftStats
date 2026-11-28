//
//  GeneratedExport.swift
//  SwiftStatsCoreTests
//
//  A generated `llvm-cov export` document, P2.6's input: its draft, and its
//  bytes, written when asked for. A failure report shows what decoding it
//  should give and the document, in ASCII (`PBTTrace.ascii`), a byte that
//  isn't UTF-8 shown as hex.
//

import Foundation
import Testing

/// A generated export document.
struct GeneratedExport: Sendable, CustomTestStringConvertible {
    /// The document as decisions.
    let draft: ExportDraft

    /// Its bytes.
    var data: Data {
        draft.data
    }

    /// What decoding it should give, then the document.
    var testDescription: String {
        let expected: String
        switch draft.expected {
        case let .accepted(files, functions):
            expected = "accepted, \(files.count) files and \(functions.count) entries"

        case .refused(let reason):
            expected = "refused: " + reason

        case .unknown:
            expected = "anything but a trap or another error"

        case .unreadable:
            expected = "refused as unreadable"
        }
        return PBTTrace.ascii("expected \(expected), fault \(draft.fault): " + GeneratedResultsFile.shown(data))
    }
}
