//
//  MarkdownIndex+TypeCheck.swift
//  SwiftStatsCore
//
//  The type-check part of the report's Build and index section (M7,
//  design §6.2, §10.1): the function-body time per project part and per
//  module, without the records nested in a body (whose entries their
//  ancestors' already hold), the 20 slowest functions with the time
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
                + "functions; totals leave out records nested in a body, whose time their ancestors hold. The total "
                + "rounds once; the figures below add each record's whole milliseconds, so they can differ from it "
                + "by rounding."
        ]
        lines += [""] + scopes(scan, build: build)
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

    /// The function-body time, the records timed and the slowest
    /// expression per project part and per module, from the records not
    /// nested in a body and the entries types and files hold.
    private static func scopes(_ scan: ScanReport, build: BuildReport) -> [String] {
        let times = moduleTimes(scan, build: build)
        let tests = Set(scan.targets.filter(\.isTest).map(\.name))
        var table = MarkdownTable(header: ["", "Function-body time (ms)", "Records timed", "Slowest expression (ms)"])
        for part in ["production", "tests"] {
            let held = times.filter { tests.contains($0.key) == (part == "tests") }.values
            table.rows.append(row(part, held.reduce(ModuleTime()) { $0.adding($1) }))
        }
        for module in times.keys.sorted() {
            table.rows.append(row(module, times[module] ?? ModuleTime()))
        }
        return table.lines(empty: "")
    }

    /// Each module's time: its records not nested in a body, and the
    /// entries its types and files hold.
    private static func moduleTimes(_ scan: ScanReport, build: BuildReport) -> [String: ModuleTime] {
        var times: [String: ModuleTime] = [:]
        let records = Dictionary(scan.records.map { ($0.key, $0) }) { first, _ in first }
        let nested = TimingMapper.nestedInBody(scan.records, types: scan.types)
        for timing in build.records {
            guard let record = records[timing.key] else {
                continue
            }
            let counted = nested.contains(timing.key) ? nil : timing.milliseconds
            let tally = ModuleTime(milliseconds: counted ?? 0, timed: 1, slowest: timing.slowestExpression)
            times[record.module, default: ModuleTime()] = times[record.module, default: ModuleTime()].adding(tally)
        }
        let fileModules = Dictionary(scan.files.map { ($0.path, $0.module) }) { first, _ in first }
        for attachment in build.attachments {
            let owner = attachment.attachedTo == .type
                ? attachment.owner.components(separatedBy: ModuleTime.moduleSeparator).first
                : fileModules[attachment.owner]
            guard let module = owner else {
                continue
            }
            let tally = ModuleTime(
                milliseconds: attachment.milliseconds ?? 0,
                timed: 0,
                slowest: attachment.slowestExpression
            )
            times[module, default: ModuleTime()] = times[module, default: ModuleTime()].adding(tally)
        }
        return times
    }

    /// A table row naming `scope` with `tally`'s figures.
    private static func row(_ scope: String, _ tally: ModuleTime) -> [String] {
        [scope, String(tally.milliseconds), String(tally.timed), MarkdownNumber.optional(tally.slowest)]
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
