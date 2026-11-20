//
//  SwiftInferTargetRun.swift
//  SwiftStatsCore
//
//  Runs `swift-infer index --target <T>` once per target (PRD §7.11), each
//  in its own clone of the copy, so each writes a fresh index, and with its
//  own `TMPDIR`, which holds the lock files and temporary directories of
//  the SwiftPM commands it starts. It does not hold the tool's manifest
//  scratch (`swift-infer-manifest-scratch`): the tool puts that in
//  Foundation's temporary directory, which on macOS is the per-user one
//  whatever `TMPDIR` says. That directory is the tool's own reusable
//  cache, shared by every run (SwiftPM's lock in it serializes them) and
//  left in place, as a run outside SwiftStats leaves it; SwiftStats can't
//  move it and doesn't remove it, since another run may be using it. At
//  most four run at once. A failure's text names the clone, the temporary
//  directory, the copy and the directory holding them as `<copy>`,
//  `<tmp>`, `<copy>` and `<work>`, so two scans fail with the same reason.
//

import Foundation

/// Runs `swift-infer index` per target.
enum SwiftInferTargetRun {
    /// Why one target's run gave no rows.
    struct Failure: Error, CustomStringConvertible, Sendable {
        /// The reason, with temporary paths named generically.
        let description: String
    }

    /// A run's invocation: the executable, the arguments after
    /// `index --target <T>`, the copy each run clones and the directory
    /// the clones are made under.
    struct Invocation: Sendable {
        /// The tool.
        let executable: URL
        /// Arguments after `index --target <T>`.
        let arguments: [String]
        /// The copy each run clones.
        let copy: URL
        /// Where the clones are made.
        let work: URL
    }

    /// The most `swift-infer` processes run at once.
    private static let maximumConcurrentRuns = 4
    /// The placeholder for a clone's root in a failure's text.
    private static let copyPlaceholder = "<copy>"
    /// The placeholder for a run's temporary directory in a failure's text.
    private static let temporaryPlaceholder = "<tmp>"
    /// The placeholder for the directory holding the copy and the clones.
    static let workPlaceholder = "<work>"

    /// Each of `targets`' rows, in their order, from runs of `invocation`.
    static func run(_ invocation: Invocation, targets: [String]) -> [Result<[SwiftInferRow], Failure>] {
        guard targets.isEmpty == false else {
            return []
        }
        let lanes = min(maximumConcurrentRuns, ProcessInfo.processInfo.activeProcessorCount, targets.count)
        let byLane = Parallel.map(Array(0..<lanes)) { lane in
            stride(from: lane, to: targets.count, by: lanes).map { index in
                (index, run(invocation, target: targets[index]))
            }
        }
        return byLane.flatMap(\.self).sorted { $0.0 < $1.0 }.map(\.1)
    }

    /// `target`'s rows from a run of `invocation` in its own clone of the copy.
    private static func run(_ invocation: Invocation, target: String) -> Result<[SwiftInferRow], Failure> {
        let (copy, work) = (invocation.copy, invocation.work)
        let directory = work.appendingPathComponent("targets").appendingPathComponent(target)
        let clone = directory.appendingPathComponent("package")
        let temporary = directory.appendingPathComponent("tmp")
        do {
            try FileManager.default.createDirectory(at: temporary, withIntermediateDirectories: true)
            try FileManager.default.copyItem(at: copy, to: clone)
            _ = try ProcessRunner.run(
                executable: invocation.executable.path,
                arguments: ["index", "--target", target] + invocation.arguments,
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
            let replacements = [
                (clone, copyPlaceholder), (temporary, temporaryPlaceholder), (copy, copyPlaceholder),
                (work, workPlaceholder)
            ]
            return .failure(Failure(description: reason(for: error, replacing: replacements)))
        }
    }

    /// The text of `error`, redacted as `redacted(_:replacing:)` does. A
    /// Foundation error gives its localized description: its full text
    /// holds paths and the addresses of underlying errors, which differ
    /// from run to run.
    static func reason(for error: any Error, replacing replacements: [(URL, String)]) -> String {
        let bridged = error as NSError
        let foundation = [NSCocoaErrorDomain, NSPOSIXErrorDomain, NSURLErrorDomain].contains(bridged.domain)
        return redacted(foundation ? bridged.localizedDescription : "\(error)", replacing: replacements)
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
