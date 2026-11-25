//
//  EvidenceUnits.swift
//  SwiftStatsCoreTests
//
//  Which units read name a record's module in the hand-made evidence of
//  `USRReasonTests` and `InactiveBranchReasonTests` (M7, design §3.4).
//

/// The units read in a reason test's evidence: none for the record's
/// module, some for another file of it, or one for the record's own file.
enum EvidenceUnits {
    /// No unit names the module.
    case absent
    /// A unit read names the module, for another file.
    case other
    /// A unit read names the module, for the record's own file.
    case own
}
