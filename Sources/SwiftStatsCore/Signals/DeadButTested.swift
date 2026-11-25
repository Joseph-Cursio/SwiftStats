//
//  DeadButTested.swift
//  SwiftStatsCore
//
//  Dead but tested (PRD §8, M7, design §8.2, D7): production functions no
//  production code uses, by outskirts' run with test targets not counted
//  as roots, whose mutants the tests run. The pool is the production
//  functions outside generated files; a function is production-dead when
//  that run's unused production entries cover it (`DeadDeclarations`).
//  A mutant of it shows a test ran it when it was killed, survived or
//  timed out, or only when killed if its file's mutation run (else its
//  own) had coverage off (`MutantsRan`). A production-dead function is listed when one of
//  its mutants ran; else it is counted, the first that applies, as in a
//  file without full mutation results (unresolved or unlisted), with no
//  mutant, with only survived or timed-out mutants in a run with coverage
//  off, with only not-covered or no-coverage mutants, with only build
//  errors. The index isn't required: without it outskirts' results are
//  mapped by position, and the payload says so. Items score by their
//  mutants that ran and sort by score, highest first, then by their
//  killing tests, most first, then subject, file and line; each carries
//  its covering declaration, its mutation results with its run's coverage
//  setting (left out when its file names no run and its mutants' runs
//  differ), and its coverage when the snapshot holds coverage. The rule
//  states both funnels: the functions, and the run's unused production
//  declarations by kind. Types and properties aren't judged. The signal
//  isn't ranked.
//

/// The dead but tested signal.
enum DeadButTested {
    /// What the signal decides of a production function.
    enum Verdict: CaseIterable, Hashable {
        /// Production-dead, its mutants only build errors.
        case buildErrors
        /// Production-dead with a mutant that ran: listed.
        case listed
        /// Production-dead with no mutant.
        case noMutant
        /// Production-dead, its mutants only not covered or no coverage.
        case notCovered
        /// Production-dead in a file without full mutation results
        /// (unresolved or unlisted).
        case partialResults
        /// Production-dead, its mutants only survived or timed out in a
        /// run with coverage off.
        case unchecked
        /// Used by production code.
        case used
    }

    /// A production function with what the signal decides of it.
    struct Judged {
        /// Its row.
        let row: FunctionRow
        /// What the signal decides of it.
        let verdict: Verdict
        /// The entry covering it; nil when it is used.
        let cover: DeadDeclarations.Cover?
        /// What the mutation results show of it.
        let facts: MutantsRan.Facts
    }

    /// The rule as reports state it, before the funnels.
    static let rule = "production functions no production code uses (outskirts with test targets not counted as "
        + "roots; public API of library-product modules, Codable and Equatable/Hashable/Comparable properties "
        + "retained) whose mutants the tests run (killed, survived or timed out; killed only, for files mutated "
        + "with coverage off); delete the code and its tests, which frees test and mutation time; a function "
        + "called only from an inactive #if branch reads as unused (outskirts' limit); types and properties "
        + "aren't judged"

    /// The dispositions of files without full mutation results.
    private static let partial: Set<MutationFileDisposition> = [.unresolved, .unlisted]

    /// The signal over `inputs`; nil when the snapshot holds no dead-code
    /// results or no mutation results.
    static func compute(_ inputs: SignalInputs) -> SignalComputation? {
        let snapshot = inputs.snapshot
        guard let dead = snapshot.deadCode?.report, let mutation = snapshot.mutation?.report else {
            return nil
        }
        let declarations = declarations(dead, index: snapshot.index?.report)
        let judged = judged(inputs, declarations: declarations, mutation: mutation)
        let payloads = FunctionPayloads(snapshot)
        let scored = judged.filter { $0.verdict == .listed }.compactMap { entry in
            item(entry, declarations: declarations, payloads: payloads)
        }
        let verdicts = judged.map(\.verdict)
        let pool = Set(judged.map(\.row.key))
        return SignalComputation(
            rule: rule + "; " + functionsFunnel(verdicts) + "; "
                + declarationsFunnel(declarations, covered: declarations.coveredByEntries(of: pool)),
            candidates: judged.count,
            scored: scored
        )
    }

    /// The unused declarations of `dead`, function entries matched by the
    /// primary and secondary USRs of `index`'s records (none without the
    /// index).
    static func declarations(_ dead: DeadCodeReport, index: IndexReport?) -> DeadDeclarations {
        let usrs = (index?.records ?? []).flatMap { [$0.usr, $0.usrAccessor].compactMap(\.self) }
        return DeadDeclarations(dead, usrs: Set(usrs))
    }

    /// The pool of `inputs`, each function with what the signal decides of
    /// it by `declarations` and `mutation`, in the snapshot's order.
    static func judged(
        _ inputs: SignalInputs,
        declarations: DeadDeclarations,
        mutation: MutationReport
    ) -> [Judged] {
        let ran = MutantsRan(mutation)
        return ProductionFunctions(inputs.snapshot).rows.map { row in
            let cover = declarations.cover(of: row.key)
            let facts = ran.facts(key: row.key, path: row.file)
            return Judged(row: row, verdict: verdict(dead: cover != nil, facts: facts), cover: cover, facts: facts)
        }
    }

    /// What the signal decides of a function, production-dead when `dead`,
    /// whose mutation results show `facts`: the first that applies.
    static func verdict(dead: Bool, facts: MutantsRan.Facts) -> Verdict {
        guard dead else {
            return .used
        }
        if facts.ran > 0 {
            return .listed
        }
        if let disposition = facts.disposition, partial.contains(disposition) {
            return .partialResults
        }
        guard let counts = facts.counts else {
            return .noMutant
        }
        if facts.unchecked > 0 {
            return .unchecked
        }
        if counts.notCovered + counts.noCoverage > 0 {
            return .notCovered
        }
        return counts.buildErrors > 0 ? .buildErrors : .noMutant
    }

    /// The functions funnel: the pool, the production-dead functions and
    /// why those not listed aren't, each part summing to its whole.
    static func functionsFunnel(_ verdicts: [Verdict]) -> String {
        let count = { (verdict: Verdict) in verdicts.count { $0 == verdict } }
        let unrun = count(.notCovered) + count(.buildErrors) + count(.noMutant) + count(.unchecked)
        let dead = verdicts.count - count(.used)
        return "\(verdicts.count) production functions = \(dead) production-dead + \(count(.used)) used; "
            + "\(dead) = \(count(.listed)) listed + \(unrun) with no mutant that ran + \(count(.partialResults)) in "
            + "files without full mutation results (unresolved or unlisted); \(unrun) = \(count(.notCovered)) only "
            + "not covered or no coverage + \(count(.buildErrors)) only build errors + \(count(.noMutant)) no "
            + "mutant + \(count(.unchecked)) only survived or timed out in a run with coverage off"
    }

    /// The declarations funnel: the `production` run's unused production
    /// entries by term, then `covered`, the pool's records the covering
    /// terms' entries cover.
    static func declarationsFunnel(_ declarations: DeadDeclarations, covered: Int) -> String {
        "\(declarations.entries) unused production declarations = "
            + "\(declarations.count(.matchedFunction)) function entries matching a record + "
            + "\(declarations.count(.unmatchedFunction)) function entries matching no record + "
            + "\(declarations.count(.typeEntry)) type entries + \(declarations.count(.extensionEntry)) extension "
            + "entries + \(declarations.count(.property)) property entries with accessor records + "
            + "\(declarations.count(.other)) others (parameters, imports, enum cases, stored properties, "
            + "typealiases); \(covered) = the distinct records F, T, E and V cover"
    }

    /// The item for the listed function `entry`; nil when it has no cover
    /// or no mutants, which a listed function always has.
    private static func item(
        _ entry: Judged,
        declarations: DeadDeclarations,
        payloads: FunctionPayloads
    ) -> SignalScore? {
        let row = entry.row
        guard let cover = entry.cover, let mutation = payloads.mutation(of: row) else {
            return nil
        }
        let declaration = cover.declaration
        let draft = SignalItem.Draft(
            subject: row.key,
            file: row.file,
            line: row.startLine,
            coverage: payloads.coverage(of: row),
            mutation: mutation.with(coverage: entry.facts.coverage),
            dead: SignalItem.Dead(
                kind: declaration.kind,
                name: declaration.name,
                file: declaration.file,
                line: declaration.line,
                via: cover.via,
                accessibility: declaration.accessibility,
                deadWithTestsAsRoots: declarations.isDeadWithTestsAsRoots(row.key)
            )
        )
        let score = Double(entry.facts.ran)
        let sortKey = SignalSortKey([
            .number(-score),
            .number(-Double(mutation.killingTests)),
            .text(row.key),
            .text(row.file),
            .number(Double(row.startLine))
        ])
        return SignalScore(draft, score: score, sortKey: sortKey)
    }
}
