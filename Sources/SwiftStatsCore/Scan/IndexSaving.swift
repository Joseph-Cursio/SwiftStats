//
//  IndexSaving.swift
//  SwiftStatsCore
//
//  What a scan that stores its snapshot adds to the T1 group it asks for
//  (M7, design §9.5): a check made once SwiftInferProperties, the coverage
//  run and the clone detector have finished and just before the build
//  starts, which stops the scan with the refusal its save would give over
//  held coverage it didn't collect (not asked for, failed or skipped) and
//  held mutation results it doesn't ask for, decided in full, records
//  included, so a build of seconds to minutes is never thrown away over
//  held results known not to carry. Held T1 results aren't decided there:
//  a build that runs replaces them.
//

/// A storing scan's part in its T1 group.
struct IndexSaving {
    /// The check before the build starts, given the coverage collector's
    /// status and the measured package; it throws the refusal that stops
    /// the scan.
    let gate: (_ coverage: CollectorStatus, _ measured: ScanMeasurements) throws -> Void
}
