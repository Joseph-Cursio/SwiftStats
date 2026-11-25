//
//  MarkdownIndex+TypeCheck.swift
//  SwiftStatsCore
//
//  The type-check part of the report's Build and index section (M7,
//  design §6.2, §10.1): the type-check roll-ups (§6.4) of each project
//  part and module, read as the scan rolled them up: the function-body
//  time without the records nested in a body (whose entries their
//  ancestors' already hold), the slowest record, the records timed and
//  the slowest expression; the 20 slowest functions with the time
//  including their local functions, the 10 slowest expressions by record,
//  the entries no record holds and those left out, and the note that two
//  builds differ by a fifth to a third per function.
//

extension MarkdownIndex {
    /// The slowest functions the section lists.
    static let listedFunctions = 20
    /// The slowest expressions the section lists.
    static let listedExpressions = 10

    /// The section's type-check part.
    static func typeCheck(_ scan: ScanReport, build: BuildReport) -> [String] {
        let records = Dictionary(scan.records.map { ($0.key, $0) }) { first, _ in first }
        let totals = build.totals
        var lines = [
            "\(totals.milliseconds) ms of function-body time from \(totals.functionEntries) function-body and "
                + "\(totals.expressionEntries) expression entries. Per record, a function's time includes its local "
                + "functions; totals leave out records nested in a body, whose time their ancestors hold, and add "
                + "the time on types and files. Each total rounds once over its own entries, so the parts can differ "
                + "from the whole by rounding; the slowest function and expression take every record."
        ]
        lines += [""] + scopes(scan)
        let timed = build.records.filter { $0.milliseconds != nil }.sorted { lhs, rhs in
            ((lhs.milliseconds ?? 0), rhs.key) > ((rhs.milliseconds ?? 0), lhs.key)
        }
        lines += ["", "Slowest functions:", ""]
        let header = ["Function", "Time (ms, including local functions)", "Slowest expression (ms)"]
        let none = "No function was timed."
        lines += MarkdownList.lines(timed, limit: listedFunctions, header: header, empty: none) { timing in
            [
                function(timing.key, in: records),
                MarkdownNumber.optional(timing.milliseconds),
                MarkdownNumber.optional(timing.slowestExpression)
            ]
        }
        let expressions = build.records.filter { $0.slowestExpression != nil }.sorted { lhs, rhs in
            ((lhs.slowestExpression ?? 0), rhs.key) > ((rhs.slowestExpression ?? 0), lhs.key)
        }
        lines += ["", "Slowest expressions, by record:", ""]
        let empty = "No expression was timed."
        let columns = ["Function", "Slowest expression (ms)"]
        lines += MarkdownList.lines(expressions, limit: listedExpressions, header: columns, empty: empty) { timing in
            [function(timing.key, in: records), MarkdownNumber.optional(timing.slowestExpression)]
        }
        let noise = "Two builds' figures differ by a fifth to a third per function; the slowest functions are what "
            + "stays stable."
        return lines + ["", leftOut(build), "", noise]
    }

    /// The type-check roll-ups (design §6.4) of each project part and
    /// each module: the function-body time, records nested in a body left
    /// out and types' and files' entries added, rounded once per scope;
    /// the slowest record; the records timed; and the slowest expression
    /// on a record.
    private static func scopes(_ scan: ScanReport) -> [String] {
        var table = MarkdownTable(header: [
            "", "Function-body time (ms)", "Slowest function (ms)", "Functions timed", "Slowest expression (ms)"
        ])
        let parts = ["production", "tests"].compactMap { part in
            scan.rollups.first { $0.scope == .project && $0.name == part }
        }
        let modules = scan.rollups.filter { $0.scope == .module }.sorted { $0.name < $1.name }
        for rollup in parts + modules {
            let figures = rollup.typecheck
            table.rows.append([
                rollup.name,
                MarkdownNumber.optional(figures?.milliseconds.total),
                MarkdownNumber.optional(figures?.milliseconds.max),
                MarkdownNumber.optional(figures?.functions.timed),
                MarkdownNumber.optional(figures?.slowestExpression.max)
            ])
        }
        return table.lines(empty: "")
    }

    /// The entries no record holds and those left out.
    private static func leftOut(_ build: BuildReport) -> String {
        let unmapped = build.unmapped
        let dropped = build.dropped
        return "On no record: \(count(unmapped.synthesized)) synthesized members, \(count(unmapped.macro)) in macro "
            + "expansions. Left out: \(count(dropped.build)) under the build directory, \(count(dropped.outsideRoot)) "
            + "outside the package root, \(count(dropped.unscanned)) in files the scan didn't parse, "
            + "\(count(dropped.fileChanged)) in files changed during the scan."
    }

    /// Entries and their time.
    private static func count(_ entries: BuildEntryCount) -> String {
        "\(entries.entries) entries (\(entries.milliseconds) ms)"
    }

    /// The record keyed `key` as the section names it, or its key when the
    /// scan has no such record.
    private static func function(_ key: String, in records: [String: FunctionRecord]) -> String {
        guard let record = records[key] else {
            return "`\(key)`"
        }
        return display(key, file: record.file, line: record.range.start.line)
    }
}
