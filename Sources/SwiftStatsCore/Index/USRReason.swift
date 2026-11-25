//
//  USRReason.swift
//  SwiftStatsCore
//
//  Why a record has no primary USR (M7, design §3.4): the first reason
//  that applies, in this order. Top-level code has no symbol;
//  a plugin target is never compiled into the store; a record under `#if`
//  in a file a unit read names as its main file (under the record's
//  target), with no definition of any kind in its range, is taken to be in
//  an inactive branch (SwiftStats never evaluates conditions; in a file no
//  unit read, the absence of definitions is no evidence, so the fault
//  reasons below come first); a file that changed during the scan isn't
//  joined; a target is not built when no unit of any class names its
//  module and the build's task log names no compile of it; a file is not
//  indexed when its target has units read but none for it; then a
//  disagreement; anything else is unexplained.
//  The last five are faults the done-when doesn't accept. The scan JSON
//  writes a reason as its raw value (`IndexRecordUSR`).
//

/// Why a record has no primary USR.
public enum USRReason: String, CaseIterable, Sendable {
    /// A record in a disagreement: several USRs, or a USR shared.
    case disagreement
    /// A record of a file that changed during the scan.
    case fileChanged
    /// A record of a file its target's units don't index.
    case fileNotIndexed
    /// A record under `#if`, in a file a unit read, with no definition in
    /// its range.
    case inactiveIfBranch
    /// A record of a plugin target, which the build never indexes.
    case pluginTarget
    /// A record of a target the build didn't compile.
    case targetNotBuilt
    /// Top-level code: compiled, but no symbol stands for it.
    case topLevelCode
    /// None of the other reasons.
    case unexplained

    /// What the reasons are judged from.
    struct Evidence {
        /// The plugin targets, by name.
        let pluginTargets: Set<String>
        /// The scanned files that changed during the scan.
        let changedFiles: Set<String>
        /// Every definition of any kind read, implicit ones included, by
        /// file.
        let definitions: [String: [SourcePosition]]
        /// The modules, as target names, of every unit of the store, of
        /// any class.
        let unitModules: Set<String>
        /// The main files of the units read, by module as a target name.
        let readFiles: [String: Set<String>]
        /// The records in a disagreement, by key.
        let inDisagreement: Set<String>
        /// Whether the build's task log names a compile of the target
        /// named.
        let compiles: (String) -> Bool
    }

    /// The phrase the reason is written as in reports.
    public var text: String {
        switch self {
        case .disagreement:
            "disagreement"

        case .fileChanged:
            "file changed during the scan"

        case .fileNotIndexed:
            "file not indexed"

        case .inactiveIfBranch:
            "inactive #if branch"

        case .pluginTarget:
            "plugin target"

        case .targetNotBuilt:
            "target not built"

        case .topLevelCode:
            "top-level code"

        case .unexplained:
            "unexplained"
        }
    }

    /// Why `record`, which has no primary USR, has none: the first reason
    /// `evidence` supports.
    static func first(for record: FunctionRecord, evidence: Evidence) -> Self {
        if record.kind == .topLevelCode {
            return .topLevelCode
        }
        if evidence.pluginTargets.contains(record.module) {
            return .pluginTarget
        }
        if record.ifConfig != nil, evidence.readFiles[record.module, default: []].contains(record.file),
           evidence.definitions[record.file, default: []].contains(where: record.range.contains) == false {
            return .inactiveIfBranch
        }
        if evidence.changedFiles.contains(record.file) {
            return .fileChanged
        }
        if evidence.unitModules.contains(record.module) == false, evidence.compiles(record.module) == false {
            return .targetNotBuilt
        }
        if let files = evidence.readFiles[record.module], files.isEmpty == false, files.contains(record.file) == false {
            return .fileNotIndexed
        }
        return evidence.inDisagreement.contains(record.key) ? .disagreement : .unexplained
    }
}
