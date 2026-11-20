//
//  EffectCollector.swift
//  SwiftStatsCore
//
//  Runs SwiftEffectInference over the production files left after
//  exclusion (PRD §7.10), in process, on the calling thread: construction
//  facts, declared tiers, strict body inference, then each site's facts,
//  joined to records by file, start and kind as complexity scores are. The
//  universe is sorted by path and uses the scan's own tree instances, since
//  SwiftEffectInference resolves some answers by node identity.
//

import SwiftEffectInference
import SwiftSyntax

/// The side-effect collector.
enum EffectCollector {
    /// The collector's name.
    static let name = "swifteffectinference"
    /// What the run is done with, recorded as the collector's options.
    static let options = [
        "calleeResolution: unique-signature",
        "maxPasses: \(StrictBodyInference.defaultMaxPasses)",
        "heuristic: import-aware, all frameworks",
        "recognition: default",
        "universe: production files after exclusion, sorted by String <"
    ]

    /// The facts of `records` found in `files`, the production files left
    /// after exclusion, with the default pass limit.
    static func run(files: [ParsedFile], records: [FunctionRecord]) throws(EffectInferenceError) -> EffectRun {
        try run(files: files, records: records, maxPasses: StrictBodyInference.defaultMaxPasses)
    }

    /// The facts of `records` found in `files`, the production files left
    /// after exclusion; fails when body inference doesn't converge within
    /// `maxPasses`.
    static func run(
        files: [ParsedFile],
        records: [FunctionRecord],
        maxPasses: Int
    ) throws(EffectInferenceError) -> EffectRun {
        try run(universe: files.sorted { $0.path < $1.path }, records: records, maxPasses: maxPasses)
    }

    /// The facts of `records` found in `universe`, taken in the order
    /// given. `run(files:records:maxPasses:)` sorts it first; this entry
    /// lets tests show what the order can and can't change.
    static func run(
        universe: [ParsedFile],
        records: [FunctionRecord],
        maxPasses: Int
    ) throws(EffectInferenceError) -> EffectRun {
        let trees = universe.map(\.tree)
        let constructionFacts = ConstructionFacts.build(from: trees)
        let inference = StrictBodyInference(trees: trees)
        let (map, passes) = try inference.converge(maxPasses: maxPasses)
        let (results, calls) = inference.explain(map: map)
        let builder = EffectFactsBuilder(
            parser: inference.parser,
            purity: PurityInferrer(constructionFacts: constructionFacts),
            inference: inference,
            results: results,
            calls: calls
        )
        let recordKeys = Dictionary(
            records.filter { $0.role == .production }.map { record in
                (joinKey(file: record.file, start: record.range.start, kind: record.kind), record.key)
            }
        ) { first, _ in first }
        var facts: [String: EffectFacts] = [:]
        for file in universe {
            let converter = SourceLocationConverter(fileName: file.path, tree: file.tree)
            for site in EffectSiteCollector.sites(in: file.tree) {
                let location = converter.location(for: site.start.positionAfterSkippingLeadingTrivia)
                let isAfterMark = location.line == 1 && file.hasByteOrderMark
                let start = SourcePosition(
                    line: location.line,
                    column: location.column + (isAfterMark ? ParsedFile.byteOrderMarkLength : 0)
                )
                if let key = recordKeys[joinKey(file: file.path, start: start, kind: site.kind)] {
                    facts[key] = builder.facts(for: site)
                }
            }
        }
        let refutedTypes = constructionFacts.refutedTypeNames.map { type in
            "\(type): \(constructionFacts.refutation(constructing: type)?.description ?? "?")"
        }
        return EffectRun(
            facts: facts,
            summary: EffectSummary(revision: EffectInferenceRevision.pinned, passes: passes, refutedTypes: refutedTypes)
        )
    }

    /// Where a record starts, and what kind it is.
    private static func joinKey(file: String, start: SourcePosition, kind: FunctionKind) -> String {
        "\(file)|\(start.line)|\(start.column)|\(kind.rawValue)"
    }
}
