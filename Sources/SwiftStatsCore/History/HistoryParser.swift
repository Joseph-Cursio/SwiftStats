//
//  HistoryParser.swift
//  SwiftStatsCore
//
//  Parses past versions of a package's Swift files into function records,
//  with the same collector and key rules as a scan, so a family's key at the
//  analysed commit is the scan's key. Files are parsed in parallel.
//

import Foundation
import SwiftParser
import SwiftSyntax

/// Parses file versions.
enum HistoryParser {
    /// Bodies shorter than this many normalised lines carry no line hashes.
    static let minimumSimilarLines = 3
    /// The fewest lines a function spans for it to have an inner body.
    private static let minimumBodySpan = 2
    /// FNV-1a's 64-bit offset basis.
    private static let hashOffsetBasis: UInt64 = 0xcbf2_9ce4_8422_2325
    /// FNV-1a's 64-bit prime.
    private static let hashPrime: UInt64 = 0x0000_0100_0000_01b3

    /// `source` at `path` in `module`, parsed as a scan parses it.
    static func parse(_ source: String, path: String, module: String, isTest: Bool) -> HistoryFile {
        let tree = Parser.parse(source: source)
        let context = FileContext(
            module: module,
            file: path,
            isTestTarget: isTest,
            testCaseClasses: [],
            converter: SourceLocationConverter(fileName: path, tree: tree),
            firstLineColumnOffset: 0
        )
        let records = KeyCollisions.resolve(FunctionCollector.collect(tree, context: context)).records
        let sourceLines = source.split(separator: "\n", omittingEmptySubsequences: false)
        var lines: [String: [UInt64]] = [:]
        for record in records {
            let hashes = bodyLineHashes(record, sourceLines: sourceLines)
            if hashes.count >= minimumSimilarLines {
                lines[record.key] = hashes
            }
        }
        return HistoryFile(rows: records.map { FunctionRow($0, snapshotId: 0) }, lines: lines)
    }

    /// The record's inner lines (its first and last lines aside), trimmed,
    /// with runs of spaces collapsed and blank and comment-only lines left
    /// out, hashed, sorted and unique.
    private static func bodyLineHashes(_ record: FunctionRecord, sourceLines: [Substring]) -> [UInt64] {
        let first = record.range.start.line
        let last = record.range.end.line
        guard last - first >= minimumBodySpan, last <= sourceLines.count else {
            return []
        }
        var hashes = Set<UInt64>()
        for line in sourceLines[first..<(last - 1)] {
            let words = line.split(whereSeparator: \.isWhitespace)
            guard let head = words.first, head.hasPrefix("//") == false else {
                continue
            }
            hashes.insert(stableHash(words.joined(separator: " ")))
        }
        return hashes.sorted()
    }

    /// FNV-1a over `text`'s UTF-8 bytes; the same in every run.
    static func stableHash(_ text: String) -> UInt64 {
        var hash = hashOffsetBasis
        for byte in text.utf8 {
            hash ^= UInt64(byte)
            hash = hash &* hashPrime
        }
        return hash
    }

    /// Each `(blob, path)` in `files` parsed, in parallel, by `blob + "\0" + path`.
    static func parseAll(
        _ files: [WantedFile],
        contents: [String: Data]
    ) -> [String: HistoryFile] {
        let parsed = Parallel.map(files) { file -> HistoryFile? in
            guard let data = contents[file.blob], let source = String(data: data, encoding: .utf8) else {
                return nil
            }
            return parse(source, path: file.path, module: file.module, isTest: file.isTest)
        }
        var result: [String: HistoryFile] = [:]
        for (file, history) in zip(files, parsed) {
            if let history {
                result[file.blob + "\u{0}" + file.path] = history
            }
        }
        return result
    }
}
