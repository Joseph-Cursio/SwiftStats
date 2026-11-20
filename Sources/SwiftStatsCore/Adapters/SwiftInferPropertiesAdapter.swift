//
//  SwiftInferPropertiesAdapter.swift
//  SwiftStatsCore
//
//  Runs SwiftInferProperties' `swift-infer index` and reads its suggestions
//  (PRD §7.11). The tool scans one target per run and works in the
//  directory it runs in, so SwiftStats copies the package once, indexes
//  each production library, executable and macro target in a clone of the
//  copy, and merges the indexes itself: the tool's own upsert would keep
//  stale rows and let the last target overwrite a shared identity. Other
//  targets, such as plugins, the tool can't index and are listed in the
//  options. Exit 0 succeeds; any other status fails the collector.
//

import Foundation

/// The SwiftInferProperties adapter.
enum SwiftInferPropertiesAdapter {
    /// The collector's name.
    static let name = "swiftinferproperties"
    /// The tool's executable.
    static let executableName = "swift-infer"
    /// Target types the tool indexes.
    static let indexedTypes: Set<String> = ["executable", "library", "macro"]
    /// The placeholder for the temporary directory in a failure's text.
    private static let workPlaceholder = "<work>"

    /// The production targets the tool indexes, sorted by name.
    static func indexed(_ targets: [TargetSummary]) -> [TargetSummary] {
        targets.filter { $0.isTest == false && indexedTypes.contains($0.type) }.sorted { $0.name < $1.name }
    }

    /// How a run over `targets` of the package at `root` is recorded: what
    /// changes the tool's output, then the targets indexed, for information.
    static func options(root: URL, targets: [TargetSummary]) -> [String] {
        let skipped = targets.filter { $0.isTest == false && indexedTypes.contains($0.type) == false }
            .sorted { $0.name < $1.name }
            .map { "\($0.name) (\($0.type))" }
        let indexed = indexed(targets).map(\.name)
        return [
            "skippedTargets: " + (skipped.isEmpty ? "none" : skipped.joined(separator: ", ")),
            "flags: index defaults (Possible included)",
            "copy: target files after exclusion, no index or decisions",
            "universe: all targets after exclusion"
        ]
            + SwiftInferCopy.settingsOptions(root: root)
            + [SwiftInferCopy.toolchainOption(root: root)]
            + ["targets: " + (indexed.isEmpty ? "none" : indexed.joined(separator: ", "))]
    }

    /// Runs `executable` over `targets` of the package at `root`.
    static func run(executable: URL, root: URL, targets: [TargetSummary]) -> SwiftInferRun {
        let options = options(root: root, targets: targets)
        let (outcome, milliseconds) = Stopwatch.time {
            Result { try indexes(executable: executable, root: root, targets: targets) }
        }
        let seiRevision = SwiftInferBuildState.effectInferenceRevision(of: executable)
        switch outcome {
        case let .success((version, merged)):
            return SwiftInferRun(
                status: CollectorStatus(name: name, state: .ran, version: version, reason: nil, options: options),
                executable: executable,
                milliseconds: milliseconds,
                merged: merged,
                seiRevision: seiRevision
            )

        case .failure(let error):
            return SwiftInferRun(
                status: CollectorStatus(name: name, state: .failed, version: nil, reason: "\(error)", options: options),
                executable: executable,
                milliseconds: milliseconds,
                merged: nil,
                seiRevision: nil
            )
        }
    }

    /// The tool's version and the merged indexes of `targets`, from runs in
    /// a temporary copy of the package at `root` that is removed after.
    private static func indexes(
        executable: URL,
        root: URL,
        targets: [TargetSummary]
    ) throws -> (version: String?, merged: MergedCandidates) {
        let work = FileManager.default.temporaryDirectory.appendingPathComponent("SwiftStats-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: work, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: work) }
        do {
            let output = try ProcessRunner.run(executable: executable.path, arguments: ["--version"], in: work)
            let version = String(bytes: output, encoding: .utf8)?.trimmingCharacters(in: .whitespacesAndNewlines)
            let copy = work.appendingPathComponent("package")
            try SwiftInferCopy.make(root: root, targets: targets, at: copy)
            let results = SwiftInferTargetRun.run(
                executable: executable,
                copy: copy,
                targets: indexed(targets).map(\.name),
                work: work
            )
            var rows: [SwiftInferRow] = []
            for result in results {
                rows += try result.get()
            }
            return (version.flatMap { $0.isEmpty ? nil : $0 }, CandidateMerge.merge(rows))
        } catch let failure as SwiftInferTargetRun.Failure {
            throw failure
        } catch {
            let reason = SwiftInferTargetRun.redacted("\(error)", replacing: [(work, workPlaceholder)])
            throw SwiftInferTargetRun.Failure(description: reason)
        }
    }
}
