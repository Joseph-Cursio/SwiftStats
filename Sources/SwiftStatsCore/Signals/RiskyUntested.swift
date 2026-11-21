//
//  RiskyUntested.swift
//  SwiftStatsCore
//
//  Risky + untested (PRD §8, M5): crash and data-race candidates. The
//  markers are defect findings in production code outside generated
//  files: crash markers (SwiftProjectLint's force unwraps, `try!` and
//  `as!`, SwiftStats' implicitly unwrapped optionals) and race markers
//  (SwiftProjectLint's `@unchecked Sendable` and `nonisolated(unsafe)`).
//  Traps, unsafe memory APIs and SwiftLint's duplicates of these rules are
//  left out and counted. Each marker is judged by `MarkerJudge`. The pool
//  is the production functions, types and files outside generated files
//  with coverage data; a function, type or file holding an untested marker
//  is listed, scored by its untested markers, then ordered by region
//  coverage, lowest first. The signal isn't ranked.
//

/// The risky + untested signal.
enum RiskyUntested {
    /// A rule whose findings are left out, and why.
    struct LeftOutRule {
        /// The tool.
        let tool: String
        /// The rule.
        let rule: String
        /// Why it is left out.
        let why: String
    }

    /// The findings left out, by tool, then rule, with why.
    static let leftOutRules = [
        LeftOutRule(tool: SwiftProjectLintAdapter.name, rule: "unconditionalTrap", why: "deliberate unreachable code"),
        LeftOutRule(tool: SwiftProjectLintAdapter.name, rule: "unsafeMemoryAPI", why: "memory safety"),
        LeftOutRule(tool: SwiftLintAdapter.name, rule: "force_cast", why: "SwiftLint's duplicate"),
        LeftOutRule(tool: SwiftLintAdapter.name, rule: "force_try", why: "SwiftLint's duplicate"),
        LeftOutRule(tool: SwiftLintAdapter.name, rule: "force_unwrapping", why: "SwiftLint's duplicate"),
        LeftOutRule(tool: SwiftLintAdapter.name, rule: "implicitly_unwrapped_optional", why: "SwiftLint's duplicate")
    ]

    /// The rule as reports state it, before the markers are counted.
    static let rule = "production functions, types and files holding a crash marker (swiftprojectlint "
        + "forceUnwrap, forceTry, forceCast; swiftstats implicitlyUnwrappedOptional) or a race marker "
        + "(swiftprojectlint uncheckedSendable, nonisolatedUnsafe) no test ran: on a line that ran 0 times, or "
        + "in a function that ran nothing; a race marker on a type is untested when none of the type's functions "
        + "but its initialisers and deinitialisers ran, and has no coverage data when none of them has any (what "
        + "is attached to the type, stored-property initialisers and lazy getters, isn't counted)"

    /// The limits the rule states after the counts.
    static let limits = "a marker on a line where other code ran reads as tested, and one reached only by "
        + "crashing exit tests reads as untested"

    /// The signal over `snapshot`; nil when it holds no coverage.
    static func compute(_ snapshot: StoredSnapshot) -> SignalComputation? {
        guard let coverage = snapshot.coverage?.report else {
            return nil
        }
        let judge = MarkerJudge(snapshot, coverage: coverage)
        let production = snapshot.findings.filter(judge.isProduction)
        var tally = MarkerTally()
        var bySubject: [RiskSubject: [(marker: RiskMarker, verdict: MarkerVerdict)]] = [:]
        for marker in RiskMarker.markers(in: production) {
            let verdict = judge.verdict(marker)
            tally.count(verdict)
            bySubject[marker.subject, default: []].append((marker, verdict))
        }
        let functions = ProductionFunctions(snapshot)
        let pool = functions.rows.filter(judge.hasData).count + judge.typesWithData().count
            + judge.filesWithData().count
        let scored = bySubject.compactMap { subject, judged in
            item(subject, judged: judged, judge: judge, functions: functions)
        }
        return SignalComputation(
            rule: rule + "; " + tally.text + "; " + leftOut(production) + "; " + limits,
            candidates: pool,
            scored: scored
        )
    }

    /// The item for `subject`, when one of its markers is untested.
    private static func item(
        _ subject: RiskSubject,
        judged: [(marker: RiskMarker, verdict: MarkerVerdict)],
        judge: MarkerJudge,
        functions: ProductionFunctions
    ) -> SignalScore? {
        let untested = judged.filter { $0.verdict == .untested }
        guard untested.isEmpty == false else {
            return nil
        }
        var byRule: [String: [Int]] = [:]
        for entry in judged {
            let counts = byRule[entry.marker.rule] ?? [0, 0]
            byRule[entry.marker.rule] = [counts[0] + (entry.verdict == .untested ? 1 : 0), counts[1] + 1]
        }
        let partlyRun = judged.filter { $0.verdict == .tested(partlyRun: true) }.count
        let first = judged.map(\.marker).min { ($0.file, $0.line ?? 0) < ($1.file, $1.line ?? 0) }
        let row = subject.target == .function ? functions.row(key: subject.name) : nil
        let file = row?.file ?? first?.file ?? subject.name
        let line = row?.startLine ?? first?.line ?? 0
        let coverage = judge.coverage(of: subject)
        let draft = SignalItem.Draft(
            subject: subject.name,
            file: file,
            line: line,
            markers: SignalItem.Markers(byRule: byRule, onPartlyRunLines: partlyRun),
            coverage: coverage
        )
        let score = Double(untested.count)
        let regions = coverage.regions.flatMap { CoverageRollup.Share.percent(covered: $0.covered, total: $0.total) }
        let order = SignalSortKey([
            .number(-score),
            .number(regions ?? .infinity),
            .text(subject.name),
            .text(file),
            .number(Double(line))
        ])
        return SignalScore(draft, score: score, sortKey: order)
    }

    /// The rule's count of the findings left out, by rule.
    private static func leftOut(_ rows: [FindingRow]) -> String {
        let counts = leftOutRules.map { entry in
            let count = rows.filter { $0.tool == entry.tool && $0.rule == entry.rule }.count
            return "\(entry.tool) \(entry.rule) \(count) (\(entry.why))"
        }
        return "left out: " + counts.joined(separator: ", ")
    }
}
