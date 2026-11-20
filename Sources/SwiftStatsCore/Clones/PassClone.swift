//
//  PassClone.swift
//  SwiftStatsCore
//
//  A class as one of SwiftCloneDetector's passes reported it, with the
//  pass named, before SwiftStats attaches it to records (PRD §7.12).
//

/// A tool-reported class and the pass that found it.
struct PassClone: Sendable {
    /// The pass.
    let pass: CloneClass.Pass
    /// The class as the tool wrote it.
    let clone: CloneDetectorOutput.Clone
    /// Whether the copies are token-identical: set on subtree classes
    /// whose copies are exactly a `--type1` class's.
    var exact = false

    /// The class's copies as a set, for comparing classes.
    var instanceSet: Set<CloneDetectorOutput.Instance> {
        Set(clone.instances)
    }
}
