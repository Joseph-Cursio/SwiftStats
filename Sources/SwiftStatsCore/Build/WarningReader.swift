//
//  WarningReader.swift
//  SwiftStatsCore
//
//  Turns the T1 build's warnings into findings (M7, design §6.3). Each
//  `warning` diagnostic becomes a `RawFinding` of tool `swiftc`: its rule
//  the diagnostic ID (`unidentified` when none was printed), its category
//  the group (none for an ungrouped warning), kind `defect`, the message
//  without its bracket suffixes, continuation lines kept, and one place. A
//  warning in a macro expansion takes the place of its `expanded code
//  originates here` note. Errors, notes and remarks aren't findings.
//  Duplicates (the emit-module job, the dependency scan, the task log's
//  copy) collapse on (place, ID or message). Places under the build
//  directory or outside the root are dropped, and counted; a warning with
//  no place in a file (a macro expansion without its origin note,
//  `<unknown>`) or in a file that changed during the scan is unmapped, and
//  counted; a place in a plugin target, which the build compiles without
//  `-debug-diagnostic-names`, is kept and counted apart. The existing
//  `FindingMapper` then attaches the places, a file the scan didn't parse
//  `unscanned`.
//

import Foundation

/// Reads the build's warnings as `swiftc` findings.
struct WarningReader {
    /// What the warnings gave.
    struct Read: Hashable {
        /// The findings, by file, line, column, rule and message.
        let findings: [RawFinding]
        /// Distinct warnings dropped: under the build directory or outside
        /// the root.
        let dropped: Int
        /// Distinct warnings left unmapped: no place in a file, or in a
        /// file that changed during the scan.
        let unmapped: Int
        /// Distinct warnings in a plugin target, which are findings too.
        let plugin: Int
    }

    /// What two copies of one warning share.
    private struct Copy: Hashable {
        /// The place's path, as printed.
        let path: String
        /// Its line.
        let line: Int
        /// Its column.
        let column: Int
        /// The ID, or the message when there is none.
        let text: String
    }

    /// The rule the `warnings:` option records: what changes it changes
    /// the findings.
    static let rule = "warning diagnostics by ID (-debug-diagnostic-names) and group, continuation lines joined, "
        + "deduplicated by place and ID, macro expansions at their origin note; dependencies and the build "
        + "directory dropped; plugin targets counted apart"
    /// The findings' tool.
    static let tool = "swiftc"
    /// The rule of a warning printed without an ID.
    static let unidentified = "unidentified"
    /// The type of a plugin target.
    static let pluginType = "plugin"

    /// The package root's real path.
    private let root: String
    /// The build directory's real path.
    private let build: String
    /// The package's targets, the longest path first.
    private let targets: [TargetSummary]
    /// The scanned files whose bytes changed during the scan.
    private let changed: Set<NFCPath>
    /// The scanned files' paths, by their NFC spelling.
    private let spellings: [NFCPath: String]

    /// A reader for the package with `targets` measured as `measured`,
    /// whose root's real path is `root`, built in the directory whose real
    /// path is `build`; the scanned files `changedFiles` (relative to the
    /// root) changed during the scan.
    init(measured: ScanMeasurements, targets: [TargetSummary], root: String, build: String, changedFiles: Set<String>) {
        self.root = root
        self.build = build
        self.targets = targets.sorted { ($0.path.count, $0.name) > ($1.path.count, $1.name) }
        changed = Set(changedFiles.map(NFCPath.init))
        spellings = Dictionary(measured.files.map { (NFCPath($0.path), $0.path) }) { first, _ in first }
    }

    /// Where `diagnostic` is: its file place, or its origin note's for a
    /// macro expansion; nil when it has neither.
    private static func place(of diagnostic: BuildDiagnostic) -> BuildPlace? {
        switch diagnostic.location {
        case .file(let place):
            place

        case .macro:
            diagnostic.origin

        case .unknown:
            nil
        }
    }

    /// Findings by file, line, column, rule, then message.
    private static func findingOrder(_ lhs: RawFinding, _ rhs: RawFinding) -> Bool {
        let left = lhs.places.first
        let right = rhs.places.first
        return (left?.file ?? "", left?.line ?? 0, left?.column ?? 0, lhs.rule, lhs.message)
            < (right?.file ?? "", right?.line ?? 0, right?.column ?? 0, rhs.rule, rhs.message)
    }

    /// The findings and counts of `diagnostics`.
    func read(_ diagnostics: [BuildDiagnostic]) -> Read {
        var seen = Set<Copy>()
        var dropped = Set<Copy>()
        var unmapped = 0
        var plugin = 0
        var findings: [RawFinding] = []
        for diagnostic in diagnostics where diagnostic.severity == .warning {
            guard let place = Self.place(of: diagnostic) else {
                unmapped += 1
                continue
            }
            let copy = Copy(
                path: place.path,
                line: place.line,
                column: place.column,
                text: diagnostic.identifier ?? diagnostic.message
            )
            guard let relative = relative(place.path) else {
                dropped.insert(copy)
                continue
            }
            guard seen.insert(copy).inserted else {
                continue
            }
            let nfc = NFCPath(relative)
            if changed.contains(nfc) {
                unmapped += 1
                continue
            }
            let path = spellings[nfc] ?? nfc.spelling
            if target(of: path)?.type == Self.pluginType {
                plugin += 1
            }
            findings.append(RawFinding(
                tool: Self.tool,
                rule: diagnostic.identifier ?? Self.unidentified,
                category: diagnostic.group,
                kind: .defect,
                severity: BuildDiagnostic.Severity.warning.rawValue,
                message: diagnostic.message,
                symbol: nil,
                places: [RawFinding.Place(file: path, line: place.line, column: place.column)]
            ))
        }
        return Read(
            findings: findings.sorted(by: Self.findingOrder),
            dropped: dropped.count,
            unmapped: unmapped,
            plugin: plugin
        )
    }

    /// `path` relative to the root; nil under the build directory or
    /// outside the root.
    private func relative(_ path: String) -> String? {
        guard path.hasPrefix(build + "/") == false, path.hasPrefix(root + "/") else {
            return nil
        }
        return String(path.dropFirst(root.count + 1))
    }

    /// The target holding the file at `path`: the one listing it, else the
    /// one whose directory holds it, the deepest first.
    private func target(of path: String) -> TargetSummary? {
        targets.first { $0.files.contains(path) }
            ?? targets.first { $0.path.isEmpty || path.hasPrefix($0.path + "/") }
    }
}
