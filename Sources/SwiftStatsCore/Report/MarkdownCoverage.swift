//
//  MarkdownCoverage.swift
//  SwiftStatsCore
//
//  The report's Coverage section (PRD §7.8, M5): how the tests ran and
//  whether the coverage was carried from an earlier scan, the test
//  bundles, line and region coverage of the production part and each
//  production module, the function records with no coverage data, the
//  public functions by how their tests are linked (a heuristic), the
//  saturated counts, the files left out by design, and the first unmapped
//  entries (all are in the JSON). When the collector didn't run, the
//  section says why.
//

/// Renders the Coverage section.
enum MarkdownCoverage {
    /// Unmapped entries the section lists; the JSON holds them all.
    static let listedUnmapped = 50

    /// The section's lines after its heading.
    static func render(_ scan: ScanReport) -> [String] {
        let status = scan.collectors.first { $0.name == CoverageAdapter.name }
        guard let coverage = scan.coverage else {
            let why = status.map { status in
                status.state.rawValue + (status.reason.map { ", \($0)" } ?? "")
            }
            return ["Not collected: \(why ?? "not in this snapshot")."]
        }
        var lines = header(coverage, reason: status?.reason)
        lines += [""] + scopes(scan)
        let partial = "Per-function coverage is a separate, partial view: functions need not add up to the totals "
            + "above, which also count code outside functions."
        lines += ["", partial]
        lines += [""] + noData(coverage)
        lines += ["", "Public functions (\(CoverageTestLinks.rule)):", ""] + publicFunctions(scan)
        lines += ["", saturated(coverage), "", dropped(coverage.dropped)]
        lines += [""] + unmapped(coverage.unmapped)
        return lines
    }

    /// How the tests ran, whether the coverage was carried, and the bundles.
    private static func header(_ coverage: CoverageReport, reason: String?) -> [String] {
        var note = reason
        var carried: String?
        if let text = reason, text.hasPrefix(CoverageCarry.carriedPrefix) {
            let rest = String(text.dropFirst(CoverageCarry.carriedPrefix.count))
            let parts = rest.components(separatedBy: "; ")
            carried = parts.first
            note = parts.count > 1 ? parts.dropFirst().joined(separator: "; ") : nil
        }
        var lines = ["Status: \(note ?? "tests \(coverage.tests)")."]
        if let carried {
            lines.append("Carried from the scan of \(carried): the tree and its functions' lines are unchanged since.")
        }
        let bundles = coverage.bundles.map { "`\($0)`" }.joined(separator: ", ")
        lines.append("Test bundles: \(bundles.isEmpty ? "none" : bundles).")
        return lines
    }

    /// Lines, regions and records by coverage data, for the production
    /// part, then each production module.
    private static func scopes(_ scan: ScanReport) -> [String] {
        var table = MarkdownTable(header: ["", "Lines", "Regions", "Functions with data", "Executed", "No data"])
        let project = scan.rollups.filter { $0.scope == .project && $0.coverage != nil }
        let modules = scan.rollups.filter { $0.scope == .module && $0.coverage != nil }.sorted { $0.name < $1.name }
        for rollup in project + modules {
            guard let coverage = rollup.coverage else {
                continue
            }
            table.rows.append([
                rollup.name,
                share(coverage.lines),
                share(coverage.regions),
                String(coverage.functions.withData),
                String(coverage.functions.executed),
                String(coverage.functions.noData)
            ])
        }
        return table.lines(empty: "No production code.")
    }

    /// The function records with no coverage data, by reason.
    private static func noData(_ coverage: CoverageReport) -> [String] {
        let reasons = Dictionary(grouping: coverage.records.compactMap(\.reason)) { $0 }
        guard reasons.isEmpty == false else {
            return ["Every production function has coverage data."]
        }
        let counts = reasons.sorted { $0.key < $1.key }.map { "\($0.value.count) \($0.key)" }
        let total = reasons.values.reduce(0) { $0 + $1.count }
        return ["Functions with no coverage data: \(total) (\(counts.joined(separator: "; ")))."]
    }

    /// The public functions by how their tests are linked, per scope.
    private static func publicFunctions(_ scan: ScanReport) -> [String] {
        var table = MarkdownTable(header: [
            "", "Public", "With coverage", "Linked", "Unlinked", "Reached generically", "Extension members",
            "Linked tests (median / p90 / max)"
        ])
        let project = scan.rollups.filter { $0.scope == .project && $0.coverage != nil }
        let modules = scan.rollups.filter { $0.scope == .module && $0.coverage != nil }.sorted { $0.name < $1.name }
        for rollup in project + modules {
            guard let functions = rollup.coverage?.publicFunctions else {
                continue
            }
            let tests = functions.linkedTests
            table.rows.append([
                rollup.name,
                String(functions.total),
                String(functions.withCoverage),
                String(functions.linked),
                String(functions.unlinked),
                String(functions.reachedGenerically),
                String(functions.extensionMembers),
                [tests.median, tests.p90, tests.max].map(MarkdownNumber.optional).joined(separator: " / ")
            ])
        }
        return table.lines(empty: "No production code.")
    }

    /// The saturated counts, which read as covered.
    private static func saturated(_ coverage: CoverageReport) -> String {
        guard coverage.saturated.isEmpty == false else {
            return "No saturated counts."
        }
        let files = Set(coverage.saturated.map(\.file)).count
        return "Saturated counts: \(coverage.saturated.count) lines in \(files) files, read as covered (parallel "
            + "tests lose counter updates, so counts can vary between runs)."
    }

    /// The export's files left out by design.
    private static func dropped(_ dropped: CoverageDropped) -> String {
        "Files left out by design: \(dropped.build) build products and dependencies, \(dropped.outsideRoot) outside "
            + "the package, \(dropped.testFiles) test files, \(dropped.otherPackage) in other packages."
    }

    /// The first unmapped entries, and how many there are.
    private static func unmapped(_ entries: [CoverageUnmapped]) -> [String] {
        guard entries.isEmpty == false else {
            return ["Every export entry in a production file was mapped."]
        }
        var table = MarkdownTable(header: ["File", "Lines", "Count", "Function", "Reason"])
        for entry in entries.prefix(listedUnmapped) {
            table.rows.append([
                entry.file,
                "\(entry.startLine)–\(entry.endLine)",
                String(entry.count),
                "`\(entry.demangled ?? entry.name)`",
                entry.reason
            ])
        }
        var lines = ["Unmapped entries: \(entries.count).", ""] + table.lines(empty: "")
        if entries.count > listedUnmapped {
            lines += ["", "\(entries.count - listedUnmapped) more in the JSON report."]
        }
        return lines
    }

    /// Covered of total, with the percentage; `no data` when nothing
    /// measured it.
    private static func share(_ share: CoverageRollup.Share?) -> String {
        guard let share else {
            return "no data"
        }
        return "\(share.covered)/\(share.total)" + (share.percent.map { " (\(MarkdownNumber.value($0))%)" } ?? "")
    }
}
