//
//  MarkerTally.swift
//  SwiftStatsCore
//
//  How risky + untested judged its markers (M5): tested, on partly run
//  lines, untested, and with no coverage data by reason, as its rule
//  states them.
//

/// Risk markers judged, by verdict.
struct MarkerTally {
    /// Markers tested.
    var tested = 0
    /// Markers tested on partly run lines.
    var partlyRun = 0
    /// Markers untested.
    var untested = 0
    /// Markers with no coverage data, by reason.
    var noData: [String: Int] = [:]

    /// The counts as the rule states them.
    var text: String {
        let total = tested + untested + noData.values.reduce(0, +)
        let reasons = noData.sorted { $0.key < $1.key }.map { "\($0.value) \($0.key)" }
        let why = reasons.isEmpty ? "" : " (" + reasons.joined(separator: ", ") + ")"
        return "\(total) markers: \(tested) tested (\(partlyRun) on partly run lines), \(untested) untested, "
            + "\(noData.values.reduce(0, +)) with no coverage data\(why)"
    }

    /// Counts `verdict`.
    mutating func count(_ verdict: MarkerVerdict) {
        switch verdict {
        case .tested(let partly):
            tested += 1
            partlyRun += partly ? 1 : 0

        case .untested:
            untested += 1

        case .noData(let reason):
            noData[reason, default: 0] += 1
        }
    }
}
