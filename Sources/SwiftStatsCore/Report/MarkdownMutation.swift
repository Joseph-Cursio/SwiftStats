//
//  MarkdownMutation.swift
//  SwiftStatsCore
//
//  The report's Mutation section (M6, design §8): the collector's status,
//  whether the results were carried from an earlier scan of the same tree
//  or merged from a `--since` run with a base snapshot, the runs that made
//  them (no run times, since a report is byte-identical), their settings,
//  the score of the production part and of each production module (over
//  merged results, labelled as such), every mutant with SwiftMutator's own
//  whole percent beside it when one full run made them all and they are
//  complete, the counts by
//  verdict and the functions by state. What follows the scores, from the
//  survivors by operator to the unmapped mutants, is in
//  `MarkdownMutation+Mutants.swift`. When the collector didn't run, the
//  section says why.
//

/// Renders the Mutation section.
enum MarkdownMutation {
    /// Unmapped mutants and changed files the section lists; the JSON
    /// holds them all.
    static let listedEntries = 50
    /// Characters of a SwiftMutator build's hash shown after `sha256:`.
    private static let shortHashLength = 10
    /// What starts a SwiftMutator build's identity.
    private static let hashPrefix = "sha256:"

    /// The section's lines after its heading.
    static func render(_ scan: ScanReport) -> [String] {
        let status = scan.collectors.first { $0.name == MutationAdapter.name }
        guard let mutation = scan.mutation else {
            let why = status.map { status in
                status.state.rawValue + (status.reason.map { ", \($0)" } ?? "")
            }
            return ["Not collected: \(why ?? "not in this snapshot")."]
        }
        var lines = header(mutation, reason: status?.reason)
        lines += [""] + runs(mutation)
        lines += ["", settings(mutation.runs)]
        lines += ["", scoreHeading(mutation), ""] + scores(scan, mutation: mutation)
        lines += ["", "Production functions by mutation state:", ""] + functions(scan)
        lines += [""] + details(mutation)
        return lines
    }

    /// How the results were made: the status, a same-tree carry, a merge
    /// with its base, and whether they are complete, naming the changed
    /// files no run retested when there are any, and list code no test
    /// ran.
    private static func header(_ mutation: MutationReport, reason: String?) -> [String] {
        var note = reason
        var carried: String?
        if let text = reason, text.hasPrefix(CollectorRunInfo.carriedPrefix) {
            let parts = String(text.dropFirst(CollectorRunInfo.carriedPrefix.count)).components(separatedBy: "; ")
            carried = parts.first
            note = parts.count > 1 ? parts.dropFirst().joined(separator: "; ") : nil
        }
        var lines = ["Status: \(note ?? "ran")."]
        if let carried {
            lines.append("Carried from the scan of \(carried): the tree and its functions' lines are unchanged since.")
        }
        if let base = mutation.base {
            lines.append("Merged: a --since run retested the files changed since \(short(base.commit)); the other "
                + "files' results are carried from its scan of \(base.collectedAt).")
        } else {
            lines.append("Made by one full run.")
        }
        let unresolved = mutation.files.count { $0.disposition == .unresolved }
        let complete = if mutation.complete {
            "Complete: every mutant the runs discovered has a result."
        } else if unresolved > 0 {
            "Incomplete: \(unresolved == 1 ? "1 changed file wasn't" : "\(unresolved) changed files weren't") "
                + "retested and \(unresolved == 1 ? "has" : "have") no results, so scores above functions are left out."
        } else {
            "Incomplete: not every mutant the runs discovered has a result, so scores above functions are left out."
        }
        let listed = mutation.listsNotCovered
            ? "Code no test ran is listed (not covered)."
            : "Code no test ran isn't listed (a SwiftMutator build before 13f96a46), so functions no test ran "
                + "aren't judged."
        return lines + [complete + " " + listed]
    }

    /// One row per run: how it ran and ended, what it tested and carried,
    /// its control runs, workers, time limit, build and toolchain.
    private static func runs(_ mutation: MutationReport) -> [String] {
        var table = MarkdownTable(header: [
            "Run", "Mode", "Commit", "Ended", "Sessions", "Mutants tested", "Not covered", "Carried",
            "Control runs (failed)", "Workers", "Time limit", "SwiftMutator build", "Toolchain"
        ])
        let byRun = Dictionary(grouping: mutation.mutants, by: \.run)
        for run in mutation.runs {
            let mutants = byRun[run.ordinal] ?? []
            let carried = mutants.count(where: \.carried)
            let source = run.carriedFrom.map { " from \(short($0.commit))" } ?? ""
            table.rows.append([
                String(run.ordinal),
                run.since.map { "since \(short($0.commit))" } ?? run.mode.rawValue,
                run.commit.map(short) ?? "no commit",
                run.endReason ?? "no end written",
                String(run.sessions),
                String(mutants.count { $0.verdict != .notCovered }),
                String(mutants.count { $0.verdict == .notCovered }),
                carried > 0 || run.carriedFrom != nil ? "\(carried)\(source)" : "0",
                "\(run.controlRuns) (\(run.controlFailures))",
                String(run.workers),
                run.timeoutSeconds.map { "\(MarkdownNumber.value($0)) s" } ?? "—",
                run.identity.map(build) ?? "—",
                run.toolchain ?? "—"
            ])
        }
        return table.lines(empty: "No runs.")
    }

    /// The settings the runs share: their operators and whether coverage
    /// was on, each run's own when they differ.
    private static func settings(_ runs: [MutationRunRecord]) -> String {
        let operators = Set(runs.map(\.operators))
        let operatorText = operators.count == 1
            ? (operators.first ?? []).joined(separator: ", ")
            : runs.map { "run \($0.ordinal): \($0.operators.joined(separator: ", "))" }.joined(separator: "; ")
        let coverage = Set(runs.map(\.skipCoverage))
        let coverageText = coverage.count == 1
            ? (coverage.first == true ? "off" : "on")
            : runs.map { "run \($0.ordinal) \($0.skipCoverage ? "off" : "on")" }.joined(separator: ", ")
        return "Settings: operators \(operatorText); coverage \(coverageText)."
    }

    /// What the score table's scores are: SwiftMutator's formula, and over
    /// merged results how many mutants were carried and from where.
    private static func scoreHeading(_ mutation: MutationReport) -> String {
        let formula = "SwiftMutator's formula: killed ÷ (killed + survived + no coverage + timed out)"
        guard let base = mutation.base else {
            return "Mutation score (\(formula)) and mutants by verdict:"
        }
        let carried = mutation.mutants.count(where: \.carried)
        let share = MutationScore.percent(killed: carried, scored: mutation.mutants.count)
            .map { "\(MarkdownNumber.value($0))%" } ?? "none"
        return "Score over merged results (\(formula); \(share) of mutants carried from \(short(base.commit))) "
            + "and mutants by verdict:"
    }

    /// The production part's and each production module's score and
    /// counts, then every mutant's, with SwiftMutator's own whole percent
    /// when one full run made them all and their results are complete (only
    /// then are SwiftStats' rows SwiftMutator's mutations).
    private static func scores(_ scan: ScanReport, mutation: MutationReport) -> [String] {
        var table = MarkdownTable(header: [
            "", "Score", "Killed", "Crash kills", "Survived", "No coverage", "Timed out", "Not covered",
            "Build errors", "Suspect-only"
        ])
        for rollup in productionScopes(scan) {
            guard let figures = rollup.mutation else {
                continue
            }
            table.rows.append([rollup.name, score(figures.score, adding: "")] + counts(figures.counts))
        }
        let every = mutation.everyMutant.counts
        let figure = MutationFigures(every).score
        let total = mutation.complete ? figure : figure.withoutPercent()
        let single = mutation.complete && mutation.mode == .full && mutation.runs.count == 1
        let own = single ? figure.truncatedPercent.map { "; SwiftMutator: \($0)%" } ?? "" : ""
        table.rows.append(["every mutant (dropped and unmapped too)", score(total, adding: own)] + counts(every))
        return table.lines(empty: "")
    }

    /// The production part's and each production module's functions by
    /// mutation state.
    private static func functions(_ scan: ScanReport) -> [String] {
        var table = MarkdownTable(header: [
            "", "Scored", "Only not covered", "Only build errors", "No mutant", "No results", "Not listed"
        ])
        for rollup in productionScopes(scan) {
            guard let functions = rollup.mutation?.functions else {
                continue
            }
            table.rows.append([
                rollup.name,
                String(functions.scored),
                String(functions.notCoveredOnly),
                String(functions.buildErrorsOnly),
                String(functions.noMutant),
                String(functions.noResults),
                String(functions.notListed)
            ])
        }
        return table.lines(empty: "No production code.")
    }

    /// The production part, then each production module, by name.
    private static func productionScopes(_ scan: ScanReport) -> [Rollup] {
        let project = scan.rollups.filter { $0.scope == .project && $0.mutation != nil }
        let modules = scan.rollups.filter { $0.scope == .module && $0.mutation != nil }.sorted { $0.name < $1.name }
        return project + modules
    }

    /// The counts of a score table row, after its score.
    private static func counts(_ counts: MutationCounts) -> [String] {
        [
            counts.killed, counts.crashKills, counts.survived, counts.noCoverage, counts.timedOut,
            counts.notCovered, counts.buildErrors, counts.suspectOnly
        ].map(String.init)
    }

    /// Killed of scored with the percentage and `adding` after it;
    /// `incomplete` when the percentage was left out, and a dash when
    /// nothing was scored.
    private static func score(_ score: MutationScore, adding: String) -> String {
        guard score.scored > 0 else {
            return "—"
        }
        let percent = score.percent.map { "\(MarkdownNumber.value($0))%" } ?? "incomplete"
        return "\(score.killed)/\(score.scored) (\(percent)\(adding))"
    }

    /// A commit as the section shows it: its first characters.
    static func short(_ commit: String) -> String {
        String(commit.prefix(MarkdownSignals.shortLength))
    }

    /// A SwiftMutator build as the section shows it: `sha256:` and the
    /// hash's first characters.
    private static func build(_ identity: String) -> String {
        guard identity.hasPrefix(hashPrefix) else {
            return identity
        }
        return hashPrefix + identity.dropFirst(hashPrefix.count).prefix(shortHashLength)
    }
}
