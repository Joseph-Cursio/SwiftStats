//
//  PackageScanner+Effects.swift
//  SwiftStatsCore
//
//  The side-effect part of a scan (PRD §7.10): SwiftEffectInference, linked
//  and run in process over the production files left after exclusion,
//  plugin targets left out, after keys are resolved and scores joined. Plugin
//  code is built for the host and never linked with the package's other
//  targets, and swift-infer skips it too, so a plugin function never makes
//  a library signature shared. It runs on the calling thread, never
//  in a concurrent loop, since inference recurses deeply on large bodies.
//  The tools' skip reason doesn't stop it: a backfill runs it too.
//

import Foundation

extension PackageScanner {
    /// The side-effect part of a scan.
    struct EffectScan {
        /// Each production record's facts, by record key; empty when the
        /// collector didn't run.
        let facts: [String: EffectFacts]
        /// The run's own outputs; nil when it didn't run.
        let summary: EffectSummary?
        /// The `swifteffectinference` collector's status.
        let status: CollectorStatus
        /// Wall-clock milliseconds.
        let milliseconds: Int

        /// `records` with each one's facts set.
        func joined(to records: [FunctionRecord]) -> [FunctionRecord] {
            records.map { record in
                var joined = record
                joined.effect = facts[record.key]
                return joined
            }
        }
    }

    /// SwiftStats' measurements with side effects joined.
    struct MeasuredScan {
        /// SwiftStats' own measurements, each production record's facts set.
        let measurements: ScanMeasurements
        /// How long measuring took, side effects apart: they are timed as
        /// their own collector.
        let milliseconds: Int
        /// The side-effect step.
        let effects: EffectScan
    }

    /// SwiftStats' own measurements of `targets`' files, with side effects
    /// joined to their records.
    static func measured(
        _ targets: [TargetSummary],
        root: URL,
        configuration: SwiftStatsConfiguration
    ) -> MeasuredScan {
        let (unjoined, milliseconds) = Stopwatch.time {
            measure(targets, root: root, configuration: configuration)
        }
        let effects = effects(of: unjoined, targets: targets, configuration: configuration)
        var measurements = unjoined
        measurements.records = effects.joined(to: unjoined.records)
        measurements.effectsCollected = effects.status.state == .ran
        return MeasuredScan(measurements: measurements, milliseconds: milliseconds, effects: effects)
    }

    /// The side effects of `measured`'s production records, found in the
    /// files of `targets` that aren't test or plugin targets, unless
    /// `configuration` disables the collector. Plugin records get no facts.
    static func effects(
        of measured: ScanMeasurements,
        targets: [TargetSummary],
        configuration: SwiftStatsConfiguration
    ) -> EffectScan {
        let name = EffectCollector.name
        guard configuration.collectors[name]?.enabled != false else {
            let reason = "disabled by collectors.\(name).enabled"
            return EffectScan(
                facts: [:],
                summary: nil,
                status: CollectorStatus(name: name, state: .skipped, version: nil, reason: reason, options: []),
                milliseconds: 0
            )
        }
        let production = Set(targets.filter { $0.isTest == false && $0.type != "plugin" }.map(\.name))
        let files = measured.parsed.filter { production.contains($0.module) }.map(\.file)
        let (outcome, milliseconds) = Stopwatch.time {
            Result { () throws(EffectInferenceError) in
                try EffectCollector.run(files: files, records: measured.records)
            }
        }
        let version = EffectInferenceRevision.pinned
        switch outcome {
        case .success(let run):
            return EffectScan(
                facts: run.facts,
                summary: run.summary,
                status: CollectorStatus(
                    name: name,
                    state: .ran,
                    version: version,
                    reason: nil,
                    options: EffectCollector.options
                ),
                milliseconds: milliseconds
            )

        case .failure(let error):
            return EffectScan(
                facts: [:],
                summary: nil,
                status: CollectorStatus(
                    name: name,
                    state: .failed,
                    version: version,
                    reason: error.description,
                    options: EffectCollector.options
                ),
                milliseconds: milliseconds
            )
        }
    }
}
