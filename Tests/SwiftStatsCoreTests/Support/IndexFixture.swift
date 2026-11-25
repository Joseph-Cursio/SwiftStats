//
//  IndexFixture.swift
//  SwiftStatsCoreTests
//
//  The Index fixture's recordings (M7, design §13), made by
//  `Scripts/record-index-fixture.sh` in `Tests/Fixtures/Index/Recorded/index/`
//  and `Tests/Fixtures/Diff/Recorded/index/`: where they are, and the
//  placeholders that stand for a recording's paths. `@ROOT@` is the package
//  root, `@BUILD@` its scratch folder (`.swiftstats/index-build`), `@DEP@`
//  IndexDep's root and `@TOOLCHAIN@` the toolchain; the build's output also
//  names `@PARENT@`, the root's parent (where Swift Build runs its tasks),
//  `@TMP@`, the temporary folder, and `@DEVELOPER@`, the developer folder
//  (`xcode-select -p`: the SDK and its frameworks). `restore` puts a run's
//  paths back and `redact` takes them out again, as the script does.
//

import Foundation
@testable import SwiftStatsCore

/// The Index fixture and its recordings.
enum IndexFixture {
    /// One placeholder and the path it stands for.
    struct Replacement {
        /// The placeholder, such as `@ROOT@`.
        let placeholder: String
        /// The path.
        let path: String
        /// Whether the path is replaced only where its last component ends.
        let wholeComponent: Bool
    }

    /// The paths a recording's placeholders stand for.
    struct Paths {
        /// The package root, `@ROOT@`.
        var root: String
        /// The scratch folder, `@BUILD@`, inside the root.
        var build: String
        /// IndexDep's root, `@DEP@`, beside the root.
        var dependency: String
        /// The toolchain, `@TOOLCHAIN@`: the folder holding `usr/bin/swift`.
        var toolchain: String
        /// The temporary folder, `@TMP@`.
        var temporary: String
        /// The developer folder, `@DEVELOPER@`: the real path of
        /// `xcode-select -p`, which usually holds the toolchain.
        var developer: String

        /// The root's parent, `@PARENT@`.
        var parent: String {
            URL(fileURLWithPath: root).deletingLastPathComponent().path
        }

        /// Each placeholder with its path, in the order `redact` replaces
        /// them: a path inside another goes first (the toolchain before the
        /// developer folder), and the root, its parent and the developer
        /// folder only where their last component ends (IndexDep's name
        /// starts with the root's).
        var replacements: [Replacement] {
            [
                Replacement(placeholder: IndexFixture.buildToken, path: build, wholeComponent: false),
                Replacement(placeholder: IndexFixture.dependencyToken, path: dependency, wholeComponent: false),
                Replacement(placeholder: IndexFixture.rootToken, path: root, wholeComponent: true),
                Replacement(placeholder: IndexFixture.parentToken, path: parent, wholeComponent: true),
                Replacement(placeholder: IndexFixture.temporaryToken, path: temporary, wholeComponent: false),
                Replacement(placeholder: IndexFixture.toolchainToken, path: toolchain, wholeComponent: false),
                Replacement(placeholder: IndexFixture.developerToken, path: developer, wholeComponent: true)
            ]
        }
    }

    /// A dump's file list (`index-check.py dump`'s `files`).
    struct DumpFiles: Decodable {
        /// The files.
        let files: [DumpFile]
    }

    /// One file of a dump: its path and the SHA-256 of its bytes.
    struct DumpFile: Decodable {
        /// The path, `@ROOT@/` and the path in the package.
        let path: String
        /// The hex SHA-256 of the file's bytes when it was recorded.
        let sha256: String
    }

    /// The package root's placeholder.
    static let rootToken = "@ROOT@"
    /// The scratch folder's placeholder.
    static let buildToken = "@BUILD@"
    /// IndexDep's placeholder.
    static let dependencyToken = "@DEP@"
    /// The toolchain's placeholder.
    static let toolchainToken = "@TOOLCHAIN@"
    /// The root's parent's placeholder.
    static let parentToken = "@PARENT@"
    /// The temporary folder's placeholder.
    static let temporaryToken = "@TMP@"
    /// The developer folder's placeholder.
    static let developerToken = "@DEVELOPER@"
    /// The environment variable naming a fresh `index-check.py dump`, which
    /// `IndexStoreReaderLiveTests` reads again with the real reader; unset,
    /// those tests are skipped.
    static let liveVariable = "SWIFTSTATS_LIVE_INDEX"

    /// The Index fixture.
    static let directory = fixtures.appendingPathComponent("Index")
    /// Its local path dependency.
    static let dependencyDirectory = fixtures.appendingPathComponent("IndexDep")
    /// The Diff fixture, whose two trees' dumps are recorded too.
    static let diffDirectory = fixtures.appendingPathComponent("Diff")
    /// The Index fixture's recordings.
    static let recordedDirectory = directory.appendingPathComponent("Recorded/index")
    /// The Diff fixture's recorded dumps, `before.json` and `after.json`.
    static let diffRecordedDirectory = diffDirectory.appendingPathComponent("Recorded/index")

    /// The recorded dumps of the first build and of the stale case.
    static let dumps = ["reader.json", "reader-stale.json"]
    /// The recorded outskirts runs.
    static let outskirtsRuns = ["outskirts-roots.json", "outskirts-production.json", "outskirts-stale-roots.json"]
    /// The recorded text files.
    static let texts = [
        "build.stdout", "build.stderr", "rebuild.stderr", "failed.stderr", "outskirts-version.txt", "toolchain.txt",
        "dependency-files.txt"
    ]
    /// Every recording of the Index fixture.
    static let recordings = dumps + outskirtsRuns + texts + ["describe.json"]

    /// The file the stale case renames, and its new name.
    static let staleRename = (
        from: "Sources/IndexCore/Formatting.swift",
        to: "Sources/IndexCore/LineFormatting.swift"
    )
    /// The stale case's edits of the manifest, moving `Relay.swift` from
    /// `index-kit` to `index-support`: the script's `kit_line` and
    /// `support_line` edits.
    static let staleManifestEdits = [
        (old: #"sources: ["Kit.swift", "Relay.swift"]"#, new: #"sources: ["Kit.swift"]"#),
        (old: #"sources: ["Support.swift"]"#, new: #"sources: ["Support.swift", "Relay.swift"]"#)
    ]

    /// `Tests/Fixtures`.
    private static let fixtures = URL(fileURLWithPath: #filePath)
        .deletingLastPathComponent()
        .deletingLastPathComponent()
        .deletingLastPathComponent()
        .appendingPathComponent("Fixtures")

    /// The bytes of the Index fixture's recording `name`.
    static func data(_ name: String) throws -> Data {
        try Data(contentsOf: recordedDirectory.appendingPathComponent(name))
    }

    /// The text of the Index fixture's recording `name`.
    static func text(_ name: String) throws -> String {
        try String(contentsOf: recordedDirectory.appendingPathComponent(name), encoding: .utf8)
    }

    /// The text of the Index fixture's recording `name` with `paths` put
    /// back.
    static func text(_ name: String, restoring paths: Paths) throws -> String {
        restore(try text(name), paths: paths)
    }

    /// The bytes of the Diff fixture's recorded dump of `side` (`before` or
    /// `after`).
    static func diffDump(_ side: String) throws -> Data {
        try Data(contentsOf: diffRecordedDirectory.appendingPathComponent("\(side).json"))
    }

    /// `text` with every placeholder replaced by its path.
    static func restore(_ text: String, paths: Paths) -> String {
        paths.replacements.reduce(text) { result, replacement in
            result.replacingOccurrences(of: replacement.placeholder, with: replacement.path)
        }
    }

    /// `text` with `paths` replaced by their placeholders, as the recording
    /// script redacts.
    static func redact(_ text: String, paths: Paths) -> String {
        paths.replacements.reduce(text) { result, replacement in
            guard replacement.wholeComponent else {
                return result.replacingOccurrences(of: replacement.path, with: replacement.placeholder)
            }
            return replacingWholeComponent(replacement.path, with: replacement.placeholder, in: result)
        }
    }

    /// `text` with `path` replaced by `placeholder` wherever the character
    /// after it can't continue a path component (a letter, a digit, `_`, `.`
    /// or `-`), or it ends the text.
    private static func replacingWholeComponent(_ path: String, with placeholder: String, in text: String) -> String {
        let pattern = NSRegularExpression.escapedPattern(for: path) + "(?![A-Za-z0-9_.-])"
        guard let expression = try? NSRegularExpression(pattern: pattern) else {
            return text
        }
        return expression.stringByReplacingMatches(
            in: text,
            range: NSRange(text.startIndex..., in: text),
            withTemplate: NSRegularExpression.escapedTemplate(for: placeholder)
        )
    }
}
