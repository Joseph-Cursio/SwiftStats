//
//  SwiftCloneDetectorAdapter.swift
//  SwiftStatsCore
//
//  Runs SwiftCloneDetector over the production files (PRD §7.12). The
//  files are given explicitly, root-relative and byte-sorted, from the
//  package root, because the tool's results depend on the set of files and
//  their order, and it forms each instance's path from the path it was
//  given. Every flag that changes results is set, so a new default
//  upstream can't change them silently. The three passes `--all` merges
//  run separately, with `--type1` beside them, four processes at once; the
//  merge happens in SwiftStats. Exits 0 (no clones) and 2 (clones) succeed;
//  64 (a usage error, or no Swift files) and anything else fail the
//  collector. With no files, the tool isn't run.
//

import Foundation

/// The SwiftCloneDetector adapter.
enum SwiftCloneDetectorAdapter {
    /// Why a run failed, without the file list the command carried.
    struct Failure: Error, CustomStringConvertible, Sendable {
        /// The reason.
        let description: String
    }

    /// The collector's name.
    static let name = "swiftclonedetector"
    /// The tool's executable.
    static let executableName = "swift-clone-detector"
    /// The part of the package read.
    static let part = "production"
    /// Flags every run passes: JSON, SwiftStats' own generated rule only,
    /// and each result-changing threshold at the tool's default.
    static let sharedArguments = [
        "--format", "json", "--include-generated", "--min-mass", "20", "--min-lines", "2",
        "--min-distinct-identifiers", "0", "--similarity", "0.85", "--min-distinctiveness", "1.55",
        "--min-identifier-overlap", "0.25"
    ]
    /// The rule choosing the files, as recorded in the options.
    static let fileRule = "files: production files after exclusion, generated ones left out, "
        + "root-relative, byte-sorted, given explicitly"
    /// The tool's `tool` field.
    private static let toolName = "swift-clone-detector"
    /// The tool's exit status when it reported clones.
    private static let clonesFound: Int32 = 2
    /// Exit statuses of a successful run: no clones, clones found.
    private static let accepted: Set<Int32> = [0, clonesFound]

    /// Each run's arguments before the files, then the file rule.
    static var options: [String] {
        CloneDetectorPass.runOrder.map { pass in
            "\(pass.label): " + (sharedArguments + pass.flags).joined(separator: " ")
        } + [fileRule]
    }

    /// The files the tool reads: production files after exclusion, less
    /// those in `generated`, sorted by their UTF-8 bytes.
    static func files(of targets: [TargetSummary], generated: Set<String>) -> [String] {
        Array(Set(targets.filter { $0.isTest == false }.flatMap(\.files)).subtracting(generated))
            .sorted { $0.utf8.lexicographicallyPrecedes($1.utf8) }
    }

    /// `sha256:<hex>` of `files`, each followed by a newline.
    static func fileListHash(_ files: [String]) -> String {
        "sha256:" + ContentHash.sha256(Data(files.map { $0 + "\n" }.joined().utf8))
    }

    /// Runs `executable` over `files` of the package at `root`.
    static func run(executable: URL, root: URL, files: [String]) -> CloneRun {
        let hash = fileListHash(files)
        guard files.isEmpty == false else {
            return CloneRun(
                status: CollectorStatus(name: name, state: .ran, version: nil, reason: nil, options: options),
                executable: executable,
                milliseconds: 0,
                fileListHash: hash,
                outputs: [:]
            )
        }
        let (results, milliseconds) = Stopwatch.time {
            Parallel.map(CloneDetectorPass.runOrder) { pass in
                Result { try output(of: pass, executable: executable, root: root, files: files) }
            }
        }
        do {
            var outputs: [CloneDetectorPass: CloneDetectorOutput] = [:]
            for (pass, result) in zip(CloneDetectorPass.runOrder, results) {
                outputs[pass] = try result.get()
            }
            let version = outputs[.subtree]?.version
            return CloneRun(
                status: CollectorStatus(name: name, state: .ran, version: version, reason: nil, options: options),
                executable: executable,
                milliseconds: milliseconds,
                fileListHash: hash,
                outputs: outputs
            )
        } catch {
            return CloneRun(
                status: CollectorStatus(name: name, state: .failed, version: nil, reason: "\(error)", options: options),
                executable: executable,
                milliseconds: milliseconds,
                fileListHash: hash,
                outputs: [:]
            )
        }
    }

    /// `pass`'s report from a run of `executable` over `files` at `root`.
    private static func output(
        of pass: CloneDetectorPass,
        executable: URL,
        root: URL,
        files: [String]
    ) throws -> CloneDetectorOutput {
        let arguments = sharedArguments + pass.flags
        let data: Data
        do {
            data = try ProcessRunner.run(
                executable: executable.path,
                arguments: arguments + files,
                in: root,
                accepting: accepted
            ).output
        } catch let ScanError.commandFailed(_, status, message) {
            let command = ([executableName] + pass.flags).joined(separator: " ")
            let count = files.count == 1 ? "1 file" : "\(files.count) files"
            throw Failure(description: "`\(command)` over \(count) exited with status \(status): \(message)")
        }
        let output: CloneDetectorOutput
        do {
            output = try JSONDecoder().decode(CloneDetectorOutput.self, from: data)
        } catch {
            throw AdapterError.unreadableOutput(name, "the \(pass.label) run: \(error)")
        }
        guard output.tool == toolName else {
            throw AdapterError.unreadableOutput(name, "the \(pass.label) run names its tool \"\(output.tool)\"")
        }
        return output
    }
}
