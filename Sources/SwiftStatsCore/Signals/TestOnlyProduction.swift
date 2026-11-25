//
//  TestOnlyProduction.swift
//  SwiftStatsCore
//
//  Test-only production code (PRD §8, M7, design §8.3, D13): production
//  functions whose only references come from test targets, by the T1
//  build's index. The pool is the production functions outside generated
//  files, each counted out by the first that applies: no USR (W, counted
//  by reason, which the funnel breaks down); public or open in a
//  library-product target (P: a library's API used only by its tests is
//  expected), by target name as the index results list them;
//  a witness or override (V); `@objc` (J: a `c:` USR); an entry point (M:
//  a parameterless `static func main()` in an executable target, the only
//  place SwiftPM builds `@main`, which the records don't keep and the
//  index never references); a deinitializer (D). The rest are candidates
//  (C), listed when tests reference them and no production code does:
//  references within a function's own family don't count, and a
//  property's reads and writes count for its reading and writing
//  accessors (design §4.1). Items score by their distinct test referrers
//  and sort by score, highest first, then subject, file and line; each
//  carries its references and, when the snapshot holds them, its coverage
//  and its mutation results. Types and properties aren't judged. The
//  signal isn't ranked.
//

import Foundation

/// The test-only production code signal.
enum TestOnlyProduction {
    /// Why a function with a USR isn't a candidate: the first that
    /// applies of public API, witness, `@objc`, entry point and
    /// deinitializer.
    enum Exclusion: CaseIterable {
        /// A deinitializer.
        case deinitializer
        /// An entry point of an executable target.
        case entryPoint
        /// An `@objc` declaration.
        case objc
        /// Public or open in a library-product target.
        case publicAPI
        /// A witness or override.
        case witness
    }

    /// What the signal decides of a production function.
    enum Verdict: Hashable {
        /// A USR, but counted out by this exclusion.
        case excluded(Exclusion)
        /// A candidate referenced from tests only: listed.
        case listed
        /// A candidate with a production reference.
        case production
        /// A candidate with no reference at all.
        case unreferenced
        /// No primary USR, for this reason (none when the index results
        /// list no record of its key).
        case withoutUSR(USRReason?)
    }

    /// A production function with what the signal decides of it.
    struct Judged {
        /// Its row.
        let row: FunctionRow
        /// What the signal decides of it.
        let verdict: Verdict
        /// Its referrers; nil when it has no primary USR.
        let references: IndexReferences?
    }

    /// What judging the pool counted.
    struct Tally: Hashable {
        /// The production functions outside generated files.
        var pool = 0
        /// Of those, the functions without a primary USR.
        var withoutUSR = 0
        /// Those, by reason (none when the index results list no record
        /// of the function's key).
        var withoutUSRByReason: [USRReason?: Int] = [:]
        /// Of those with one, the functions each exclusion counted out.
        var excluded: [Exclusion: Int] = [:]
        /// The candidates listed: referenced from tests only.
        var listed = 0
        /// The candidates with a production reference.
        var production = 0
        /// The candidates with no reference at all.
        var unreferenced = 0

        /// The functions with a primary USR.
        var withUSR: Int {
            pool - withoutUSR
        }

        /// The candidates: functions with a USR no exclusion counted out.
        var candidates: Int {
            listed + production + unreferenced
        }

        /// `verdicts` counted.
        init(_ verdicts: [Verdict]) {
            pool = verdicts.count
            for verdict in verdicts {
                switch verdict {
                case .withoutUSR(let reason):
                    withoutUSR += 1
                    withoutUSRByReason[reason, default: 0] += 1

                case .excluded(let exclusion):
                    excluded[exclusion, default: 0] += 1

                case .listed:
                    listed += 1

                case .production:
                    production += 1

                case .unreferenced:
                    unreferenced += 1
                }
            }
        }

        /// The functions `exclusion` counted out.
        func count(_ exclusion: Exclusion) -> Int {
            excluded[exclusion] ?? 0
        }

        /// The functions without a primary USR for `reason`.
        func count(_ reason: USRReason?) -> Int {
            withoutUSRByReason[reason] ?? 0
        }
    }

    /// The rule as reports state it, before the funnel.
    static let rule = "production functions whose only references come from test targets (index: calls, reads and "
        + "writes; references within the function's own family don't count, and a property's reads and writes count "
        + "for its reading and writing accessors); public API of library-product modules, witnesses and overrides, "
        + "@objc declarations, entry points of executable targets and deinitializers are left out and counted; either "
        + "dead or missing a production caller; types and properties aren't judged"

    /// The accesses that make a library-product target's function its API.
    private static let libraryAccess: Set<FunctionAccess> = [.public, .open]
    /// The prefix of an Objective-C symbol's USR.
    private static let objcPrefix = "c:"
    /// The declaration an entry point's key ends with, between spaces or
    /// the ends.
    private static let entryPoint = "static func main()"
    /// The separator of a key's segments.
    private static let keySeparator = "::"
    /// The separator of a collided key's location suffix.
    private static let suffixSeparator = " @ "
    /// What the funnel calls the reason of a function whose key the index
    /// results list no record of.
    static let noReasonStored = "no reason stored"

    /// The signal over `inputs`; nil when the snapshot holds no index
    /// results.
    static func compute(_ inputs: SignalInputs) -> SignalComputation? {
        guard let index = inputs.snapshot.index?.report else {
            return nil
        }
        let judged = judged(inputs, index: index)
        let payloads = FunctionPayloads(inputs.snapshot)
        let scored = judged.filter { $0.verdict == .listed }.map { entry in
            item(entry.row, references: entry.references, payloads: payloads)
        }
        let tally = Tally(judged.map(\.verdict))
        return SignalComputation(rule: rule + "; " + funnel(tally), candidates: tally.pool, scored: scored)
    }

    /// The pool of `inputs`, each function with what the signal decides of
    /// it by `index`, the snapshot's index results, in the snapshot's
    /// order.
    static func judged(_ inputs: SignalInputs, index: IndexReport) -> [Judged] {
        let usrs = Dictionary(index.records.map { ($0.key, $0) }) { first, _ in first }
        let library = Set(index.libraryModules)
        let executables = inputs.snapshot.executableTargets
        return ProductionFunctions(inputs.snapshot).rows.map { row in
            guard let record = usrs[row.key], let usr = record.usr else {
                return Judged(row: row, verdict: .withoutUSR(usrs[row.key]?.reason), references: nil)
            }
            let references = record.coupling?.references
            let excluded = exclusion(of: row, usr: usr, record: record, library: library, executables: executables)
            if let excluded {
                return Judged(row: row, verdict: .excluded(excluded), references: references)
            }
            let tests = references?.tests ?? 0
            let production = (references?.sameModule ?? 0) + (references?.otherModules ?? 0)
            let verdict: Verdict = production > 0 ? .production : tests > 0 ? .listed : .unreferenced
            return Judged(row: row, verdict: verdict, references: references)
        }
    }

    /// The funnel from the production functions to the listed ones, each
    /// part summing to its whole.
    static func funnel(_ tally: Tally) -> String {
        let withUSR = tally.withUSR
        let candidates = tally.candidates
        return "\(tally.pool) production functions = \(tally.withoutUSR) without a USR\(byReason(tally)) + "
            + "\(withUSR) with one; "
            + "\(withUSR) = \(tally.count(.publicAPI)) public API of a library product + "
            + "\(tally.count(.witness)) witnesses or overrides + \(tally.count(.objc)) @objc + "
            + "\(tally.count(.entryPoint)) entry points + \(tally.count(.deinitializer)) deinitializers + "
            + "\(candidates) candidates; \(candidates) = \(tally.listed) listed + \(tally.production) with a "
            + "production reference + \(tally.unreferenced) with no reference at all (not listed: fan-in 0 isn't "
            + "dead, PRD §7.6a)"
    }

    /// The functions without a primary USR by reason, in parentheses, in
    /// `USRReason`'s order with the stored reason missing last; nothing
    /// when every function has one.
    static func byReason(_ tally: Tally) -> String {
        let reasons: [USRReason?] = USRReason.allCases + [nil]
        let parts = reasons.compactMap { reason -> String? in
            let count = tally.count(reason)
            return count > 0 ? "\(count) \(reason?.text ?? noReasonStored)" : nil
        }
        return parts.isEmpty ? "" : " (" + parts.joined(separator: ", ") + ")"
    }

    /// The first exclusion that applies to `row`, whose primary USR is
    /// `usr` and whose index facts are `record`, with `library` the
    /// library-product targets and `executables` the executable ones; nil
    /// for a candidate.
    private static func exclusion(
        of row: FunctionRow,
        usr: String,
        record: IndexRecordUSR,
        library: Set<String>,
        executables: Set<String>
    ) -> Exclusion? {
        if let access = row.access, libraryAccess.contains(access), library.contains(row.module) {
            return .publicAPI
        }
        if record.coupling?.witness == true {
            return .witness
        }
        if usr.hasPrefix(objcPrefix) {
            return .objc
        }
        if isEntryPoint(row, executables: executables) {
            return .entryPoint
        }
        if row.kind == .deinitializer {
            return .deinitializer
        }
        return nil
    }

    /// Whether `row` is a parameterless `static func main()` in one of
    /// `executables`: its key's last segment, before any collision
    /// suffix, holds that declaration between spaces or the ends.
    static func isEntryPoint(_ row: FunctionRow, executables: Set<String>) -> Bool {
        guard row.kind == .function, row.name == "main", (row.parameterCount ?? 0) == 0,
              executables.contains(row.module) else {
            return false
        }
        var declaration = Substring(row.key)
        if let separator = declaration.range(of: keySeparator, options: .backwards) {
            declaration = declaration[separator.upperBound...]
        }
        if let suffix = declaration.range(of: suffixSeparator) {
            declaration = declaration[..<suffix.lowerBound]
        }
        return " \(declaration) ".contains(" \(entryPoint) ")
    }

    /// The item for `row`, referenced only from tests by `references`.
    private static func item(
        _ row: FunctionRow,
        references: IndexReferences?,
        payloads: FunctionPayloads
    ) -> SignalScore {
        let tests = references?.tests ?? 0
        let draft = SignalItem.Draft(
            subject: row.key,
            file: row.file,
            line: row.startLine,
            coverage: payloads.coverage(of: row),
            mutation: payloads.mutation(of: row),
            references: SignalItem.References(
                tests: tests,
                testReferrers: references?.testReferrers ?? [],
                module: row.module
            )
        )
        return SignalScore(draft, score: Double(tests))
    }
}
