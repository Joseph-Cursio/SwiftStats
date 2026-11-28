//
//  GitChanges.swift
//  SwiftStatsCore
//
//  What git says changed between an earlier snapshot's commit and a later
//  one (PRD §8, divergent clones): the commits after the earlier one, and
//  the old-side ranges of a zero-context diff of the package, following
//  renames and ignoring whitespace. Read-only git; every setting that
//  could change the diff's hunks is fixed, as the history walk fixes its
//  own: on the command line, and in the environment for GIT_DIFF_OPTS,
//  whose `--unified` overrides `-U0`. Every file is diffed as text, so
//  neither a `-diff` or `binary` attribute (from the user's attributes
//  file too) nor `core.bigFileThreshold` turns a file's hunks into
//  "Binary files differ". Only Swift files are diffed: clone copies are
//  only in them, and as text a changed image or model asset would put all
//  its bytes in the diff. The pathspec's glob is explicit and the setting
//  that would read it literally is cleared, so no exported pathspec
//  setting changes which files it names. The commit list is plain
//  `rev-list` output, which no diff or log setting changes.
//

import Foundation

/// Reads the commits and diff hunks between two commits.
enum GitChanges {
    /// Pairs renames among this many files at most, as the history walk does.
    private static let renameLimit = 100_000
    /// Starts a file's part of a diff.
    private static let fileMarker = "diff --git "
    /// Starts a file's old path in a diff header.
    private static let oldPathMarker = "--- "
    /// Starts a hunk.
    private static let hunkMarker = "@@ "
    /// The most digits an octal escape in a quoted path has.
    private static let octalDigits = 3
    /// The base of an octal escape.
    private static let octalRadix = 8
    /// The byte git writes as `\a`.
    private static let bell: UInt8 = 0x07
    /// The byte git writes as `\b`.
    private static let backspace: UInt8 = 0x08
    /// The byte git writes as `\v`.
    private static let verticalTab: UInt8 = 0x0B
    /// The byte git writes as `\f`.
    private static let formFeed: UInt8 = 0x0C
    /// The package's Swift files, at any depth below the working directory.
    static let swiftFiles = ":(glob)**/*.swift"
    /// The environment settings that would change the diff's hunks, or the
    /// files `swiftFiles` names, cleared: git ignores an empty
    /// GIT_DIFF_OPTS, and reads its magic and glob unless pathspecs are
    /// literal.
    static let pinnedEnvironment = ["GIT_DIFF_OPTS": "", "GIT_LITERAL_PATHSPECS": "0"]

    /// The commits reachable from `later` and not from `earlier`.
    static func commits(from earlier: String, to later: String, in directory: URL) throws -> Set<String> {
        let data = try ProcessRunner.run(
            executable: GitReader.git,
            arguments: ["--no-optional-locks", "rev-list", "\(earlier)..\(later)", "--"],
            in: directory
        )
        return Set((String(bytes: data, encoding: .utf8) ?? "").split(separator: "\n").map(String.init))
    }

    /// The old-side ranges of the diff from `earlier` to `later` of the
    /// package at `packagePath` (from the repository's top level), whose
    /// root is `directory`, by the earlier commit's path from the package root.
    static func hunks(
        from earlier: String,
        to later: String,
        packagePath: String,
        in directory: URL
    ) throws -> [String: [DiffHunk]] {
        try hunks(from: earlier, to: later, packagePath: packagePath, in: directory, inherited: [:])
    }

    /// The hunks as `hunks(from:to:packagePath:in:)` reads them, with
    /// `inherited` added to this process's environment, as a setting the
    /// user exported would be; the pinned settings win over both.
    static func hunks(
        from earlier: String,
        to later: String,
        packagePath: String,
        in directory: URL,
        inherited: [String: String]
    ) throws -> [String: [DiffHunk]] {
        let arguments = [
            "--no-optional-locks", "-c", "core.quotepath=off", "-c", "diff.renames=true",
            "diff", "-M", "-l\(renameLimit)", "-w", "-U0", "--inter-hunk-context=0", "--diff-algorithm=myers",
            "--indent-heuristic", "--no-ext-diff", "--no-textconv", "--text", "--no-color", "--no-relative",
            "--ignore-submodules", "--src-prefix=a/", "--dst-prefix=b/", earlier, later, "--", swiftFiles
        ]
        let data = try ProcessRunner.run(
            executable: GitReader.git,
            arguments: arguments,
            in: directory,
            environment: inherited.merging(pinnedEnvironment) { _, pinned in pinned }
        )
        return hunks(inDiff: text(of: data), packagePath: packagePath)
    }

    /// The diff output `data` as text, each line decoded on its own: as
    /// UTF-8, else as Latin-1. So a changed line of a file that isn't UTF-8
    /// spoils only itself, not the raw UTF-8 paths in other files' headers.
    static func text(of data: Data) -> String {
        data.split(separator: UInt8(ascii: "\n"), omittingEmptySubsequences: false)
            .map { line in
                String(bytes: line, encoding: .utf8) ?? String(bytes: line, encoding: .isoLatin1) ?? ""
            }
            .joined(separator: "\n")
    }

    /// The old-side ranges of the zero-context diff `text`, by old path
    /// relative to the package at `packagePath`. Files new in the later
    /// commit, and files outside the package, have none. Lines end at each
    /// LF scalar, as git ends them: a CR LF pair is one `Character`, so
    /// splitting on `Character("\n")` would join a CRLF file's changed line
    /// to the hunk or file header after it (design B5).
    static func hunks(inDiff text: String, packagePath: String) -> [String: [DiffHunk]] {
        let prefix = ["a"] + (packagePath.isEmpty ? [] : components(of: packagePath))
        var hunks: [String: [DiffHunk]] = [:]
        var path: String?
        var inHeader = false
        for scalars in text.unicodeScalars.split(separator: "\n", omittingEmptySubsequences: false) {
            let line = Substring(scalars)
            if line.hasPrefix(fileMarker) {
                (path, inHeader) = (nil, true)
            } else if inHeader, line.hasPrefix(oldPathMarker) {
                path = relative(unquoted(String(line.dropFirst(oldPathMarker.count))), below: prefix)
            } else if line.hasPrefix(hunkMarker) {
                inHeader = false
                if let path, let hunk = hunk(line) {
                    hunks[path, default: []].append(hunk)
                }
            }
        }
        return hunks
    }

    /// The components of `path`, split at each `/` scalar.
    private static func components(of path: String) -> [String] {
        path.unicodeScalars.split(separator: "/", omittingEmptySubsequences: false).map { String($0) }
    }

    /// The header path `old` from below the folder whose components are
    /// `prefix` (`a` and the package path's), or nil when it doesn't lie
    /// below it. Compared component by component, the `/`s found among
    /// Unicode scalars: a component starting with a combining mark, a
    /// joiner or a spacing mark joins the `/` before it into one
    /// `Character`, which a `Character` prefix test would miss (design
    /// B35). Each component compares as Swift strings do, so a package path
    /// spelled in the other normalization form than git's still matches.
    private static func relative(_ old: String, below prefix: [String]) -> String? {
        let parts = components(of: old)
        guard parts.count > prefix.count, zip(parts, prefix).allSatisfy(==) else {
            return nil
        }
        return parts.dropFirst(prefix.count).joined(separator: "/")
    }

    /// The old side of the hunk header `line` (`@@ -start[,count] …`).
    private static func hunk(_ line: Substring) -> DiffHunk? {
        let fields = line.split(separator: " ")
        guard fields.count > 1, fields[1].hasPrefix("-") else {
            return nil
        }
        let range = fields[1].dropFirst().split(separator: ",", omittingEmptySubsequences: false)
        guard let start = range.first.flatMap({ Int($0) }) else {
            return nil
        }
        guard range.count > 1 else {
            return DiffHunk(start: start, count: 1)
        }
        return Int(range[1]).map { DiffHunk(start: start, count: $0) }
    }

    /// A header path as git wrote it, without the tab git adds after a
    /// name with spaces, and unquoted when git quoted it (`"a/x\ty"`),
    /// through every escape git writes: the letters `a b t n v f r`, a
    /// quote and a backslash, and octal ones (design B34).
    private static func unquoted(_ written: String) -> String {
        let path = written.hasSuffix("\t") ? String(written.dropLast()) : written
        guard path.count > 1, path.hasPrefix("\""), path.hasSuffix("\"") else {
            return path
        }
        var bytes: [UInt8] = []
        var characters = Array(path.dropFirst().dropLast().utf8)[...]
        while let byte = characters.popFirst() {
            guard byte == UInt8(ascii: "\\"), let escaped = characters.popFirst() else {
                bytes.append(byte)
                continue
            }
            bytes.append(contentsOf: unescaped(escaped, rest: &characters))
        }
        return String(bytes: bytes, encoding: .utf8) ?? path
    }

    /// The bytes the escape `\<escaped>` stands for, taking the rest of
    /// an octal escape from `rest`.
    private static func unescaped(_ escaped: UInt8, rest: inout ArraySlice<UInt8>) -> [UInt8] {
        switch escaped {
        case UInt8(ascii: "a"):
            return [bell]

        case UInt8(ascii: "b"):
            return [backspace]

        case UInt8(ascii: "f"):
            return [formFeed]

        case UInt8(ascii: "n"):
            return [UInt8(ascii: "\n")]

        case UInt8(ascii: "r"):
            return [UInt8(ascii: "\r")]

        case UInt8(ascii: "t"):
            return [UInt8(ascii: "\t")]

        case UInt8(ascii: "v"):
            return [verticalTab]

        case UInt8(ascii: "0")...UInt8(ascii: "7"):
            let octal = UInt8(ascii: "0")...UInt8(ascii: "7")
            var digits = [escaped]
            while digits.count < octalDigits, let next = rest.first, octal.contains(next) {
                digits.append(next)
                rest.removeFirst()
            }
            return [UInt8(String(bytes: digits, encoding: .utf8) ?? "0", radix: octalRadix) ?? 0]

        default:
            return [escaped]
        }
    }
}
