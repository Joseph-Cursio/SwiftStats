//
//  SwiftInferTargetRun.swift
//  SwiftStatsCore
//
//  Runs `swift-infer index --target <T>` once per target (PRD §7.11), each
//  in its own clone of the copy, so each writes a fresh index, and with its
//  own `TMPDIR`, where the tool evaluates the manifest. At most four run at
//  once. A failure's text names the clone and the temporary directory as
//  `<copy>` and `<tmp>`, so two scans fail with the same reason.
//

import Foundation

/// Runs `swift-infer index` per target.
enum SwiftInferTargetRun {
    /// Why one target's run gave no rows.
    struct Failure: Error, CustomStringConvertible, Sendable {
        /// The reason, with temporary paths named generically.
        let description: String
    }

    /// The most `swift-infer` processes run at once.
    private static let maximumConcurrentRuns = 4
    /// The placeholder for a clone's root in a failure's text.
    private static let copyPlaceholder = "<copy>"
    /// The placeholder for a run's temporary directory in a failure's text.
    private static let temporaryPlaceholder = "<tmp>"

    /// Each of `targets`' rows, in their order, from runs of `executable`
    /// in clones of `copy` made under `work`.
    static func run(executable: URL, copy: URL, targets: [String], work: URL) -> [Result<[SwiftInferRow], Failure>] {
        guard targets.isEmpty == false else {
            return []
        }
        let lanes = min(maximumConcurrentRuns, ProcessInfo.processInfo.activeProcessorCount, targets.count)
        let byLane = Parallel.map(Array(0..<lanes)) { lane in
            stride(from: lane, to: targets.count, by: lanes).map { index in
                (index, run(executable: executable, copy: copy, target: targets[index], work: work))
            }
        }
        return byLane.flatMap(\.self).sorted { $0.0 < $1.0 }.map(\.1)
    }

    /// `target`'s rows from a run of `executable` in its own clone of `copy`.
    private static func run(executable: URL, copy: URL, target: String, work: URL) -> Result<[SwiftInferRow], Failure> {
        let directory = work.appendingPathComponent("targets").appendingPathComponent(target)
        let clone = directory.appendingPathComponent("package")
        let temporary = directory.appendingPathComponent("tmp")
        do {
            try FileManager.default.createDirectory(at: temporary, withIntermediateDirectories: true)
            try FileManager.default.copyItem(at: copy, to: clone)
            _ = try ProcessRunner.run(
                executable: executable.path,
                arguments: ["index", "--target", target],
                in: clone,
                accepting: [0],
                environment: ["TMPDIR": temporary.path + "/"]
            )
            let index = clone.appendingPathComponent(SwiftInferCopy.settingsDirectory)
                .appendingPathComponent("index.json")
            guard let data = try? Data(contentsOf: index) else {
                let written = "\(SwiftInferCopy.settingsDirectory)/index.json"
                let reason = "`swift-infer index --target \(target)` wrote no \(written)"
                throw AdapterError.unreadableOutput(SwiftInferPropertiesAdapter.name, reason)
            }
            return .success(try SwiftInferIndex.decode(data).rows(target: target, root: clone))
        } catch {
            let replacements = [(clone, copyPlaceholder), (temporary, temporaryPlaceholder)]
            return .failure(Failure(description: redacted("\(error)", replacing: replacements)))
        }
    }

    /// `text` with each directory in `replacements`, however it is
    /// spelled (`/var/…` or `/private/var/…`), replaced by its placeholder.
    static func redacted(_ text: String, replacing replacements: [(URL, String)]) -> String {
        var redacted = text
        for (directory, placeholder) in replacements {
            for spelling in PathSpellings.of(directory) {
                redacted = redacted.replacingOccurrences(of: spelling, with: placeholder)
            }
        }
        return redacted
    }
}
