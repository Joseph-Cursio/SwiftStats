//
//  SwiftInferCopy.swift
//  SwiftStatsCore
//
//  The package as `swift-infer index` sees it (PRD §7.11): a temporary copy
//  holding the manifest and any versioned ones (`Package@swift-6.0.swift`,
//  which SwiftPM reads in its place), its resolved pins, the toolchain pin, every
//  target's files left after exclusion (tests too, which its test lifter
//  reads) and SwiftInferProperties' own settings: `config.toml` and the
//  vocabulary file it names, or the conventional `vocabulary.json`. Files
//  are copied as bytes, symlinks followed. A target file the measure step
//  skips, one unreadable or not UTF-8, is left out too, so both tools see
//  one universe. The index, decisions and verify evidence are never
//  copied: the tool upserts into an index it finds and joins decisions
//  itself, and SwiftStats joins those from the package instead.
//

import Foundation

/// Builds the copy `swift-infer` runs in.
enum SwiftInferCopy {
    /// SwiftInferProperties' settings directory.
    static let settingsDirectory = ".swiftinfer"
    /// The settings file that changes the tool's results and can name its
    /// vocabulary.
    private static let configFile = "config.toml"
    /// The toolchain pin swiftly reads.
    private static let toolchainPin = ".swift-version"
    /// The manifest files copied when present; `Package.swift` must be.
    private static let manifestFiles = ["Package.swift", "Package.resolved"]
    /// The prefix of a versioned manifest's name.
    private static let versionedManifestPrefix = "Package@swift-"

    /// A copy of the package at `root` with `targets`' files, made at
    /// `copy`, which must not exist.
    static func make(root: URL, targets: [TargetSummary], at copy: URL) throws {
        let fileManager = FileManager.default
        try fileManager.createDirectory(at: copy, withIntermediateDirectories: true)
        let settings = ["\(settingsDirectory)/\(configFile)"]
            + [SwiftInferVocabulary.of(root: root).copiedPath].compactMap(\.self)
        let optional = Set(manifestFiles.dropFirst())
        for path in manifestFiles + (try versionedManifests(in: root)) {
            let source = root.appendingPathComponent(path)
            if optional.contains(path), fileManager.fileExists(atPath: source.path) == false {
                continue
            }
            try write(Data(contentsOf: source), to: copy.appendingPathComponent(path))
        }
        // The settings are copied when readable: the tool reads one it
        // can't, or a directory in its place, as it reads no file.
        for path in settings {
            guard let data = try? Data(contentsOf: root.appendingPathComponent(path)) else {
                continue
            }
            try write(data, to: copy.appendingPathComponent(path))
        }
        // The measure step skips, with a warning, a file it can't read as
        // UTF-8 (`PackageScanner.parseFiles`); so does the copy.
        for path in targets.flatMap(\.files) {
            guard let data = try? Data(contentsOf: root.appendingPathComponent(path)),
                  String(data: data, encoding: .utf8) != nil else {
                continue
            }
            try write(data, to: copy.appendingPathComponent(path))
        }
        // The tool finds a target at `Sources/<name>` or the manifest's
        // path, so each target's directory exists even when exclusion
        // left it no files.
        for target in targets where target.path.isEmpty == false {
            try fileManager.createDirectory(
                at: copy.appendingPathComponent(target.path),
                withIntermediateDirectories: true
            )
        }
        if let pin = toolchainPin(for: root) {
            try write(Data(contentsOf: pin), to: copy.appendingPathComponent(toolchainPin))
        }
    }

    /// The versioned manifests at the top of the package at `root`, sorted.
    private static func versionedManifests(in root: URL) throws -> [String] {
        try FileManager.default.contentsOfDirectory(atPath: root.path)
            .filter { $0.hasPrefix(versionedManifestPrefix) && $0.hasSuffix(".swift") }
            .sorted()
    }

    /// The `.swift-version` that applies to the package at `root`: its own,
    /// else the nearest in a directory above it, up to its repository's top
    /// level, or, outside a repository, as far as swiftly looks: to the
    /// root of the file system. An export of a nested package
    /// (`RevisionExport`) is outside a repository and has its repository's
    /// pin just above it. nil when there is none.
    static func toolchainPin(for root: URL) -> URL? {
        let fileManager = FileManager.default
        var directory = root.resolvingSymlinksInPath()
        let top = GitReader.line(["rev-parse", "--show-toplevel"], in: root)
            .map { URL(fileURLWithPath: $0).resolvingSymlinksInPath().path }
        while true {
            let pin = directory.appendingPathComponent(toolchainPin)
            if fileManager.fileExists(atPath: pin.path) {
                return pin
            }
            // Above `/`, the URL would grow `/..` components forever.
            let parent = directory.deletingLastPathComponent().standardizedFileURL
            guard parent.path != directory.path else {
                return nil
            }
            if let top, directory.path == top || directory.path.hasPrefix(top + "/") == false {
                return nil
            }
            directory = parent
        }
    }

    /// The toolchain pin that applies to the package at `root` as an
    /// option, since it picks the compiler that evaluates the manifest:
    /// `.swift-version: <its text, trimmed>`, or `.swift-version: absent`.
    static func toolchainOption(root: URL) -> String {
        let text = toolchainPin(for: root)
            .flatMap { try? String(contentsOf: $0, encoding: .utf8) }?
            .trimmingCharacters(in: .whitespacesAndNewlines)
        return "\(toolchainPin): " + (text ?? "absent")
    }

    /// The settings of the package at `root` as options:
    /// `config.toml: sha256:<hex>`, or `config.toml: absent`, then the
    /// vocabulary that applies (`SwiftInferVocabulary.option`).
    static func settingsOptions(root: URL) -> [String] {
        let config = root.appendingPathComponent(settingsDirectory).appendingPathComponent(configFile)
        let hash = ContentHash.sha256(ofFileAt: config).map { "sha256:\($0)" } ?? "absent"
        return ["\(configFile): " + hash, SwiftInferVocabulary.of(root: root).option]
    }

    /// Writes `data` to `url`, creating its directory.
    private static func write(_ data: Data, to url: URL) throws {
        try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        try data.write(to: url)
    }
}
