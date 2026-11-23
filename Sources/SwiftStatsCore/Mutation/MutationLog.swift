//
//  MutationLog.swift
//  SwiftStatsCore
//
//  `.swiftstats/mutation/swift-mutator.log` (M6, design §1.2): the
//  standard output and standard error of a mutation step's warm build,
//  SwiftMutator run and report, appended in turn, never piped, since a run
//  prints progress lines for hours. Emptied when a step starts, and kept
//  after it, so the user can read what SwiftMutator said. SwiftStats adds
//  a line before each command and one after it with its exit and its
//  time, from which the warm build's and SwiftMutator's times are read
//  apart. A command's part of the log is read back from the offset it
//  started at, for the reason of a failure and SwiftMutator's results
//  path.
//

import Foundation

/// A mutation step's log.
struct MutationLog {
    /// What starts the lines SwiftStats adds.
    static let marker = "=== swiftstats: "

    /// The log file.
    let url: URL

    /// The log at `url`, emptied (made when missing).
    static func started(at url: URL) throws(MutationFailure) -> Self {
        guard FileManager.default.createFile(atPath: url.path, contents: Data()) else {
            throw MutationFailure(description: "could not write .swiftstats/mutation/\(url.lastPathComponent)")
        }
        return Self(url: url)
    }

    /// How many bytes the log holds: where the next command's output starts.
    func offset() -> UInt64 {
        let size = (try? FileManager.default.attributesOfItem(atPath: url.path)[.size]) as? UInt64
        return size ?? 0
    }

    /// Appends `line` and a newline, prefixed with `marker`.
    func note(_ line: String) {
        guard let handle = try? FileHandle(forWritingTo: url) else {
            return
        }
        defer { try? handle.close() }
        _ = try? handle.seekToEnd()
        try? handle.write(contentsOf: Data((Self.marker + line + "\n").utf8))
    }

    /// The log's text from byte `start` to its end, read as Latin-1 when
    /// it isn't UTF-8.
    func text(from start: UInt64) -> String {
        guard let handle = try? FileHandle(forReadingFrom: url) else {
            return ""
        }
        defer { try? handle.close() }
        try? handle.seek(toOffset: start)
        let data = (try? handle.readToEnd()) ?? Data()
        return String(bytes: data, encoding: .utf8) ?? String(bytes: data, encoding: .isoLatin1) ?? ""
    }

    /// The text from `start`, without the lines SwiftStats added.
    func output(from start: UInt64) -> String {
        text(from: start)
            .split(separator: "\n", omittingEmptySubsequences: false)
            .filter { $0.hasPrefix(Self.marker) == false }
            .joined(separator: "\n")
    }
}
