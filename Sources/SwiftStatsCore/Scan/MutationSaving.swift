//
//  MutationSaving.swift
//  SwiftStatsCore
//
//  What a scan that stores its snapshot adds to the SwiftMutator run it
//  asks for (M6, design §6.4, as built; M7, design §9.5): a check made
//  once every other collector has finished and just before SwiftMutator
//  starts, which stops the scan with the refusal its save would give over
//  held coverage it didn't collect and held T1 results whose build it
//  didn't run (not asked for, failed or skipped), decided in full, so an
//  hour-long run is never thrown away over held results known not to
//  carry; and, for a run that ran, `pending.json` kept until the snapshot
//  is stored, so a save that is still refused can be resumed without
//  running SwiftMutator again.
//

/// A storing scan's part in its SwiftMutator run.
struct MutationSaving {
    /// The check before SwiftMutator starts, given the coverage
    /// collector's status, the `build` collector's and the measured
    /// package; it throws the refusal that stops the scan.
    let gate: (_ coverage: CollectorStatus, _ build: CollectorStatus, _ measured: ScanMeasurements) throws -> Void
}
