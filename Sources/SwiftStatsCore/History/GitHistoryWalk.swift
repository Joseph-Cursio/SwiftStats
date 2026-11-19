//
//  GitHistoryWalk.swift
//  SwiftStatsCore
//
//  The commits behind a package (PRD §7.13): one `git log` over the package
//  directory, newest first in topological order, merges left out (their
//  changes are in the merged commits), each with the files it changed.
//  Every setting that could change git's output is pinned on the command
//  line, so a user's git configuration can't change the history.
//

import Foundation

/// Reads a package's commits.
enum GitHistoryWalk {
    /// Git's all-zero blob name, for a side with no file.
    private static let missingBlob = String(repeating: "0", count: blobNameLength)
    /// The length of a full git blob name.
    private static let blobNameLength = 40
    /// The log fields before the first changed file: hash, time, subject,
    /// body and the empty field ending the format.
    private static let fieldsBeforeChanges = 5
    /// The position of the subject among a commit's log fields.
    private static let subjectField = 2
    /// The position of the body among a commit's log fields.
    private static let bodyField = 3
    /// The parts of a raw diff line: modes, blobs and status.
    private static let rawPartCount = 5
    /// The position of the blob before among a raw diff line's parts.
    private static let oldBlobPart = 2
    /// The position of the blob after among a raw diff line's parts.
    private static let newBlobPart = 3
    /// The position of the status among a raw diff line's parts.
    private static let statusPart = 4
    /// The parts of an `ls-tree` entry before its tab: mode, type and blob.
    private static let treeEntryPartCount = 3
    /// Starts each commit in the output.
    private static let commitMarker = UInt8(ascii: "\u{01}")
    /// Pairs renames among this many files at most; fixed so every machine
    /// pairs the same way.
    private static let renameLimit = 100_000

    /// The commits reachable from `commit` that changed the package at
    /// `packagePath` (from the repository's top level `top`), newest first.
    static func commits(top: URL, commit: String, packagePath: String) throws -> [HistoryCommit] {
        let arguments = [
            "--no-optional-locks", "-c", "core.quotepath=off", "-c", "diff.renames=true",
            "log", commit, "--no-merges", "--topo-order", "--root", "--no-relative", "--raw", "-M",
            "-l\(renameLimit)", "--no-abbrev", "-z", "--no-show-signature", "--no-color", "--no-mailmap",
            "--no-ext-diff", "--no-textconv",
            "--format=%x01%H%x00%ct%x00%s%x00%b%x00",
            "--", packagePath.isEmpty ? "." : packagePath
        ]
        let data = try ProcessRunner.run(executable: GitReader.git, arguments: arguments, in: top)
        let prefix = packagePath.isEmpty ? "" : packagePath + "/"
        // Each commit is decoded on its own, so a message that isn't UTF-8
        // spoils only its own commit's text (read as Latin-1), not the walk.
        return data.split(separator: commitMarker).compactMap { chunk in
            let text = String(bytes: chunk, encoding: .utf8) ?? String(bytes: chunk, encoding: .isoLatin1) ?? ""
            return parse(text, prefix: prefix)
        }
    }

    /// One commit's part of the output, or nil for the empty part before the first.
    private static func parse(_ chunk: String, prefix: String) -> HistoryCommit? {
        let fields = chunk.components(separatedBy: "\u{0}")
        guard fields.count >= fieldsBeforeChanges, let time = Int(fields[1]) else {
            return nil
        }
        var changes: [FileChange] = []
        var index = fieldsBeforeChanges
        while index < fields.count {
            let token = fields[index].trimmingCharacters(in: .newlines)
            index += 1
            guard token.hasPrefix(":") else {
                continue
            }
            let parts = token.split(separator: " ")
            guard parts.count >= rawPartCount, let status = parts[statusPart].first, index < fields.count else {
                continue
            }
            let first = fields[index]
            index += 1
            var second: String?
            if status == "R" || status == "C", index < fields.count {
                second = fields[index]
                index += 1
            }
            let oldBlob = parts[oldBlobPart] == missingBlob ? nil : String(parts[oldBlobPart])
            let newBlob = parts[newBlobPart] == missingBlob ? nil : String(parts[newBlobPart])
            let (before, after) = second.map { (first, $0) } ?? (first, first)
            changes.append(FileChange(
                status: status,
                oldPath: oldBlob == nil || status == "C" ? nil : relative(before, prefix: prefix),
                newPath: newBlob == nil ? nil : relative(after, prefix: prefix),
                oldBlob: status == "C" ? nil : oldBlob,
                newBlob: newBlob
            ))
        }
        return HistoryCommit(
            hash: fields[0],
            time: time,
            subject: fields[subjectField],
            body: fields[bodyField],
            changes: changes
        )
    }

    /// `path` relative to the package, or nil when it is outside it.
    private static func relative(_ path: String, prefix: String) -> String? {
        guard path.hasPrefix(prefix) else {
            return nil
        }
        return String(path.dropFirst(prefix.count))
    }

    /// The files of the package at `commit`, with their blobs, relative to
    /// the package root; none when the commit doesn't hold the package's
    /// directory yet, whose code is then all uncommitted.
    static func files(top: URL, commit: String, packagePath: String) throws -> [String: String] {
        let tree = packagePath.isEmpty ? commit : "\(commit):\(packagePath)"
        guard packagePath.isEmpty || GitReader.output(["cat-file", "-e", tree], in: top) != nil else {
            return [:]
        }
        let data = try ProcessRunner.run(
            executable: GitReader.git,
            arguments: ["--no-optional-locks", "-c", "core.quotepath=off", "ls-tree", "-r", "-z", "--full-tree", tree],
            in: top
        )
        var files: [String: String] = [:]
        let listing = String(bytes: data, encoding: .utf8) ?? ""
        for entry in listing.split(separator: "\u{0}") {
            // `<mode> blob <hash>\t<path>`
            guard let tab = entry.firstIndex(of: "\t") else {
                continue
            }
            let head = entry[..<tab].split(separator: " ")
            guard head.count == treeEntryPartCount, head[1] == "blob", let blob = head.last else {
                continue
            }
            files[String(entry[entry.index(after: tab)...])] = String(blob)
        }
        return files
    }
}
