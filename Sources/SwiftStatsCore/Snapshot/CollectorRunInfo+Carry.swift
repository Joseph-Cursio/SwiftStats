//
//  CollectorRunInfo+Carry.swift
//  SwiftStatsCore
//
//  A collector run as a rescan that carries its results records it (M5,
//  M6, M7, design §6.4, §9.4): coverage, mutation and T1 results are
//  collected only when a scan asks for them, so a rescan of the same tree
//  that didn't collect them keeps the run that did, its identity, version,
//  options and duration, with a reason saying when the results were
//  collected, followed by the reason the collecting run gave, which a run
//  carried before still holds after its own date. A carried coverage or
//  SwiftMutator run reads `ran`; a carried T1 run keeps the state it ended
//  in, since the `index` or `periphery` collector may have failed after a
//  build that ran.
//

extension CollectorRunInfo {
    /// The start of a carried run's reason, before the collection date.
    static let carriedPrefix = "carried from the scan of "
    /// What separates the parts of a carried run's reason.
    private static let reasonSeparator = "; "

    /// The status a scan report lists for this run.
    var status: CollectorStatus {
        CollectorStatus(name: name, state: state, version: version, reason: reason, options: options)
    }

    /// This run as a rescan that carries its results, collected at
    /// `collectedAt`, records it: state `ran`, its reason saying when they
    /// were collected, then the reason this run gave, without repeating a
    /// date an earlier carry put there.
    func carried(collectedAt: String) -> Self {
        carried(collectedAt: collectedAt, keeping: .ran)
    }

    /// This run as `carried(collectedAt:)` records it, but in `state`.
    func carried(collectedAt: String, keeping state: CollectorState) -> Self {
        let carried = Self.carriedPrefix + collectedAt
        var original = reason
        if let text = original, text.hasPrefix(carried) {
            let rest = text.dropFirst(carried.count)
            original = rest.hasPrefix(Self.reasonSeparator) ? String(rest.dropFirst(Self.reasonSeparator.count)) : nil
        }
        return Self(
            name: name,
            state: state,
            reason: original.map { carried + Self.reasonSeparator + $0 } ?? carried,
            version: version,
            identity: identity,
            identityLabel: identityLabel,
            options: options,
            durationMilliseconds: durationMilliseconds
        )
    }
}
