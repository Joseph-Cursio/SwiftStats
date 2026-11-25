//
//  DeadButTested.swift
//  SwiftStatsCore
//
//  Dead but tested (PRD §8, M7, design §8.2, D7): production functions no
//  production code uses, by outskirts' run with test targets not counted as
//  roots, whose mutants the tests run. The pool is the production functions
//  outside generated files; a function is production-dead when that run's
//  unused production entries cover it (`DeadDeclarations`), or cover the
//  nearest covered record up its `parentKey` chain, whose cover it
//  inherits: outskirts lists only the outermost unused declaration, and the
//  mutation mapper puts a mutant on the innermost record, so a dead
//  subscript's explicit accessors and a dead function's local functions
//  hold its mutants. Only the outermost production-dead record of such a
//  nest is judged and listed, its facts taken over itself and the records
//  nested in it; those are counted apart, as nested in it. A mutant of it
//  shows a test ran it when it was killed, survived or timed out, or only
//  when killed if its file's mutation run (else its own) had coverage off
//  (`MutantsRan`). A production-dead function is listed when one of its
//  mutants ran; else it is counted, the first that applies, as in a file
//  without full mutation results (unresolved or unlisted), with no mutant,
//  with only survived or timed-out mutants in a run with coverage off, with
//  only not-covered or no-coverage mutants, with only build errors. The
//  index isn't required: without it outskirts' results are mapped by
//  position, and the payload says so. Items score by their mutants that ran
//  and sort by score, highest first, then by their killing tests, most
//  first, then subject, file and line; each carries its covering
//  declaration, whether the `roots` run covers it or a record it is nested
//  in, its mutation results (with the records nested in it) with its
//  run's coverage setting (left out when its file names no run and its
//  mutants' runs differ), and its coverage when the snapshot holds
//  coverage. The rule states both funnels: the functions, and the run's
//  unused production declarations by kind. Types and properties aren't
//  judged. The signal isn't ranked.
//

/// The dead but tested signal.
enum DeadButTested {
    /// What the signal decides of a production function.
    enum Verdict: Hashable {
        /// Production-dead, its mutants only build errors.
        case buildErrors
        /// Production-dead with a mutant that ran: listed.
        case listed
        /// Nested in a production-dead function (an accessor, a local
        /// function), which is judged with its mutants.
        case nested
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
        /// What the mutation results show of it, with the records nested
        /// in it when it is judged with them.
        let facts: MutantsRan.Facts
        /// The keys judged together: its own, with those of the records
        /// nested in it when it is the outermost production-dead record of
        /// a nest.
        let keys: Set<String>
        /// Whether the `roots` run covers it or its nearest ancestor that
        /// run covers.
        let deadWithTestsAsRoots: Bool
    }

    /// The rule as reports state it, before the funnels.
    static let rule = "production functions no production code uses (outskirts with test targets not counted as "
        + "roots; public API of library-product modules and the package modules they re-export, Codable and "
        + "Equatable/Hashable/Comparable properties retained) whose mutants the tests run (killed, survived or timed "
        + "out; killed only, for files mutated with coverage off); a function nested in a production-dead one (an "
        + "accessor, a local function) is dead with it, and only the outermost is judged and listed, with the "
        + "mutants of all of them; delete the code and its tests, which frees test and mutation time; a function "
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
            item(entry, payloads: payloads)
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
    /// it by `declarations` and `mutation`, in the snapshot's order: a
    /// function is production-dead when it or a record up its `parentKey`
    /// chain in the pool is covered, with the nearest one's cover; the
    /// outermost covered record of a chain is judged with the facts of
    /// every pool record whose chain reaches it, and those are nested.
    static func judged(
        _ inputs: SignalInputs,
        declarations: DeadDeclarations,
        mutation: MutationReport
    ) -> [Judged] {
        let ran = MutantsRan(mutation)
        let rows = ProductionFunctions(inputs.snapshot).rows
        let parents = Dictionary(rows.map { ($0.key, $0.parentKey) }) { first, _ in first }
        let chains = Dictionary(rows.map { ($0.key, chain(of: $0.key, parents: parents)) }) { first, _ in first }
        let outermost = chains.compactMapValues { chain in chain.last { declarations.cover(of: $0) != nil } }
        let nests = Dictionary(grouping: outermost.keys) { outermost[$0] ?? "" }
        return rows.map { row in
            let chain = chains[row.key] ?? [row.key]
            let cover = chain.lazy.compactMap(declarations.cover(of:)).first
            let outer = outermost[row.key]
            let keys = outer == row.key ? (nests[row.key] ?? [row.key]).sorted(by: CodePointOrder.precedes) : [row.key]
            let facts = ran.facts(keys: keys, path: row.file)
            let judgement: Verdict = switch outer {
            case nil:
                .used

            case row.key:
                verdict(dead: true, facts: facts)

            default:
                .nested
            }
            return Judged(
                row: row,
                verdict: judgement,
                cover: cover,
                facts: facts,
                keys: Set(keys),
                deadWithTestsAsRoots: chain.contains(where: declarations.isDeadWithTestsAsRoots)
            )
        }
    }

    /// The keys from `key` up its parent chain by `parents` (the pool's
    /// parent keys), `key` first, as far as a parent outside the pool; a
    /// key met twice ends it.
    private static func chain(of key: String, parents: [String: String?]) -> [String] {
        var chain = [key]
        var seen: Set<String> = [key]
        while let last = chain.last, let parent = parents[last].flatMap(\.self), parents[parent] != nil,
              seen.insert(parent).inserted {
            chain.append(parent)
        }
        return chain
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
    /// why those not listed aren't, those nested in another apart, each
    /// part summing to its whole.
    static func functionsFunnel(_ verdicts: [Verdict]) -> String {
        let count = { (verdict: Verdict) in verdicts.count { $0 == verdict } }
        let unrun = count(.notCovered) + count(.buildErrors) + count(.noMutant) + count(.unchecked)
        let dead = verdicts.count - count(.used)
        return "\(verdicts.count) production functions = \(dead) production-dead + \(count(.used)) used; "
            + "\(dead) = \(count(.listed)) listed + \(unrun) with no mutant that ran + \(count(.partialResults)) in "
            + "files without full mutation results (unresolved or unlisted) + \(count(.nested)) nested in one of "
            + "those, judged with it; \(unrun) = \(count(.notCovered)) only not covered or no coverage + "
            + "\(count(.buildErrors)) only build errors + \(count(.noMutant)) no mutant + \(count(.unchecked)) only "
            + "survived or timed out in a run with coverage off"
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
    private static func item(_ entry: Judged, payloads: FunctionPayloads) -> SignalScore? {
        let row = entry.row
        guard let cover = entry.cover, let mutation = payloads.mutation(of: row, with: entry.keys) else {
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
                deadWithTestsAsRoots: entry.deadWithTestsAsRoots
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
