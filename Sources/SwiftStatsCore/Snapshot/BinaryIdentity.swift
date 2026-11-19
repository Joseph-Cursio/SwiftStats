//
//  BinaryIdentity.swift
//  SwiftStatsCore
//
//  An external tool's build identity (PRD §6.2): the SHA-256 of its binary,
//  with the commit of its source as a label only when that commit is surely
//  the one the binary was built from.
//

import Foundation

/// Identifies an external tool's build.
enum BinaryIdentity {
    /// The name of SwiftPM's build directory.
    private static let buildDirectoryName = ".build"

    /// The identity and label of the binary at `executable`; nil when it
    /// can't be read.
    static func of(_ executable: URL) -> (identity: String, label: String?)? {
        let binary = executable.resolvingSymlinksInPath()
        guard let hash = ContentHash.sha256(ofFileAt: binary) else {
            return nil
        }
        return ("sha256:\(hash)", sourceCommit(of: binary))
    }

    /// The commit of the package whose `.build` holds `binary`, when that
    /// package is the top level of a clean work tree and the binary is newer
    /// than both HEAD's last move (its reflog) and every tracked file;
    /// otherwise nil. HEAD alone would name a binary built before a pull
    /// with the commit after it, and a commit's own date predates the pull.
    private static func sourceCommit(of binary: URL) -> String? {
        var directory = binary.deletingLastPathComponent()
        while directory.lastPathComponent != buildDirectoryName {
            let parent = directory.deletingLastPathComponent()
            guard parent.path != directory.path else {
                return nil
            }
            directory = parent
        }
        let package = directory.deletingLastPathComponent()
        guard GitReader.isTopLevel(package), GitReader.isClean(package),
              let commit = GitReader.line(["rev-parse", "HEAD"], in: package),
              let moved = headMoved(in: package),
              let built = modified(binary),
              built > moved, built > newestTrackedFile(in: package) else {
            return nil
        }
        return "git:\(commit)"
    }

    /// When HEAD last moved, from its reflog; nil without one.
    private static func headMoved(in package: URL) -> Date? {
        // `%gd` with `--date=unix` prints `HEAD@{<seconds>}`.
        guard let entry = GitReader.line(["reflog", "-n", "1", "--date=unix", "--format=%gd", "HEAD"], in: package),
              let seconds = TimeInterval(entry.filter(\.isNumber)) else {
            return nil
        }
        return Date(timeIntervalSince1970: seconds)
    }

    /// When the newest tracked file in `package` was modified.
    private static func newestTrackedFile(in package: URL) -> Date {
        let paths = GitReader.output(["ls-files", "-z"], in: package)?
            .split(separator: 0)
            .compactMap { String(bytes: $0, encoding: .utf8) } ?? []
        return paths.compactMap { modified(package.appendingPathComponent($0)) }.max() ?? .distantPast
    }

    /// When the file at `url` was last modified.
    private static func modified(_ url: URL) -> Date? {
        try? url.resourceValues(forKeys: [.contentModificationDateKey]).contentModificationDate
    }
}
