//
//  CloneDetectorPass.swift
//  SwiftStatsCore
//
//  The four runs of `swift-clone-detector` a scan makes (PRD §7.12): the
//  three passes `--all` merges, each run on its own so SwiftStats knows
//  which pass found each class, and `--type1`, which tells exact subtree
//  classes from renamed ones.
//

/// One run of `swift-clone-detector`.
enum CloneDetectorPass: CaseIterable, Sendable {
    /// `--type3`: near-miss classes.
    case nearMiss
    /// `--sequence`: runs of identical sibling statements or members.
    case sequence
    /// No pass flag: subtree classes, identifiers and literals renamed.
    case subtree
    /// `--type1`: subtree classes with token-identical copies.
    case type1

    /// The runs in the order they are listed and their results kept.
    static let runOrder: [Self] = [.subtree, .nearMiss, .sequence, .type1]

    /// The pass's own flags.
    var flags: [String] {
        switch self {
        case .nearMiss:
            return ["--type3"]

        case .sequence:
            return ["--sequence"]

        case .subtree:
            return []

        case .type1:
            return ["--type1"]
        }
    }

    /// The pass's name in options and failure reasons.
    var label: String {
        switch self {
        case .nearMiss:
            return "near-miss"

        case .sequence:
            return "sequence"

        case .subtree:
            return "subtree"

        case .type1:
            return "type1"
        }
    }

    /// The merged classes' pass for this run; nil for `--type1`, whose
    /// classes only mark subtree classes exact.
    var classPass: CloneClass.Pass? {
        switch self {
        case .nearMiss:
            return .nearMiss

        case .sequence:
            return .sequence

        case .subtree:
            return .subtree

        case .type1:
            return nil
        }
    }
}
