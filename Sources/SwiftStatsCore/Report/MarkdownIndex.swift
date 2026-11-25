//
//  MarkdownIndex.swift
//  SwiftStatsCore
//
//  The report's Build and index section (M7, design §10.1), read only
//  from stored facts (no run times): the status of the `build` and
//  `index` collectors with a carry's date apart, the build's options in
//  one line, the index store's units by class, then the records with a
//  USR per part and module, those without one by reason, the USR and key
//  disagreements, the definitions with no record (apart, by sub-reason)
//  and the key collisions a USR separates. Module edges, fan-in and type
//  cycles are in `MarkdownIndex+Coupling.swift`; type-check times in
//  `MarkdownIndex+TypeCheck.swift`; compiler warnings in
//  `MarkdownIndex+Warnings.swift`. Lists print at most 50 rows, saying
//  how many there are; the JSON lists all. When the build didn't run, the
//  section says why.
//

/// Renders the Build and index section.
enum MarkdownIndex {
    /// The reasons for no USR that code not compiled in this build
    /// configuration, or compiled outside the store, gives.
    private static let notCompiledHere: Set<USRReason> = [.inactiveIfBranch, .pluginTarget, .topLevelCode]
    /// What a USR of an Objective-C declaration starts with.
    private static let objcPrefix = "c:"
    /// The build options the section names, by what each starts with.
    private static let namedOptions = ["toolchain: ", ".swift-version: ", "rebuild: "]

    /// The section's lines after its heading.
    static func render(_ scan: ScanReport) -> [String] {
        let build = scan.collectors.first { $0.name == BuildAdapter.name }
        let index = scan.collectors.first { $0.name == IndexAdapter.name }
        guard scan.build != nil || scan.index != nil else {
            return ["Not collected: \(MarkdownCarry.state(build))."]
        }
        var lines = ["Status: build \(MarkdownCarry.state(build)); index \(MarkdownCarry.state(index))."]
        if let carried = MarkdownCarry.carried(build) ?? MarkdownCarry.carried(index) {
            lines.append("Carried from the scan of \(carried): the tree, its records, types and files are unchanged "
                + "since.")
        }
        if let options = build.map(options) {
            lines.append(options)
        }
        if let report = scan.build, report.complete == false {
            lines.append("Timings are incomplete: the build found no root intermediates to remove, so files it "
                + "didn't recompile have no timings.")
        }
        if let report = scan.index {
            lines += ["", units(report.store)]
            lines += ["", "### USRs", ""] + usrs(scan, index: report)
            lines += ["", "### Coupling", ""] + coupling(report)
        }
        if let report = scan.build {
            lines += ["", "### Type-check time", ""] + typeCheck(scan, build: report)
            lines += ["", "### Compiler warnings", ""] + warnings(scan, build: report)
        }
        return lines
    }

    /// The build's toolchain, its `.swift-version` and what each build
    /// rebuilds, in one line.
    private static func options(_ status: CollectorStatus) -> String {
        let named = namedOptions.compactMap { lead in status.options.first { $0.hasPrefix(lead) } }
        return "Build options: " + (named.isEmpty ? "none recorded" : named.joined(separator: "; ")) + "."
    }

    /// The store's units by class, and what was read.
    private static func units(_ store: IndexStoreSummary) -> String {
        let counts = store.counts
        return "Index store units: \(counts.kept) kept, \(counts.variant) variants, \(counts.duplicate) "
            + "duplicates; \(counts.stale) stale and \(counts.otherModule) other-module units "
            + "(\(counts.quarantined) moved out of the store); \(counts.system) system and \(counts.otherPackage) "
            + "other-package units not read. Index records read: \(store.records), with \(store.occurrences) "
            + "occurrences."
    }

    /// Every USR part: the records with one, those without, the
    /// disagreements, the definitions with no record and the collisions.
    private static func usrs(_ scan: ScanReport, index: IndexReport) -> [String] {
        var lines = withUSR(scan, index: index)
        lines += [""] + withoutUSR(scan, index: index)
        lines += ["", "USR and key disagreements:", ""] + disagreements(index.disagreements)
        lines += [""] + withoutRecord(index.withoutRecord)
        lines += ["", "Key collisions the USR separates:", ""] + collisions(index.collisions)
        return lines
    }

    /// The records with a primary USR, of all records, per project part
    /// and then per module, with the secondary accessor USRs and `c:`
    /// USRs among them.
    private static func withUSR(_ scan: ScanReport, index: IndexReport) -> [String] {
        let tests = Set(scan.targets.filter(\.isTest).map(\.name))
        let modules = Dictionary(scan.records.map { ($0.key, $0.module) }) { first, _ in first }
        let facts = Dictionary(grouping: index.records) { modules[$0.key] ?? "" }
        let project = scan.rollups.filter { $0.scope == .project && $0.index != nil }
        let perModule = scan.rollups.filter { $0.scope == .module && $0.index != nil }.sorted { $0.name < $1.name }
        var table = MarkdownTable(header: ["", "Records with a USR", "Secondary accessor USRs", "`c:` USRs"])
        for rollup in project + perModule {
            guard let counts = rollup.index else {
                continue
            }
            let held = rollup.scope == .module
                ? facts[rollup.name, default: []]
                : facts.filter { tests.contains($0.key) == (rollup.name == "tests") }.flatMap(\.value)
            let total = counts.withUSR + counts.withoutUSR.values.reduce(0, +)
            table.rows.append([
                rollup.name,
                "\(counts.withUSR) of \(total)",
                String(held.count { $0.usrAccessor != nil }),
                String(held.count { $0.usr?.hasPrefix(objcPrefix) == true })
            ])
        }
        return table.lines(empty: "No records.")
    }

    /// The records without a primary USR by reason, with the sentence
    /// saying every compiled record has one when the only reasons are
    /// code this configuration doesn't compile into the store.
    private static func withoutUSR(_ scan: ScanReport, index: IndexReport) -> [String] {
        let facts = Dictionary(index.records.map { ($0.key, $0) }) { first, _ in first }
        let missing = scan.records.compactMap { record -> (record: FunctionRecord, reason: USRReason)? in
            guard let held = facts[record.key] else {
                return (record, .unexplained)
            }
            return held.usr == nil ? (record, held.reason ?? .unexplained) : nil
        }
        var lines: [String] = []
        if missing.allSatisfy({ notCompiledHere.contains($0.reason) }) {
            lines.append("Every compiled record has a USR.")
        }
        guard missing.isEmpty == false else {
            return lines
        }
        let counts = USRReason.allCases.compactMap { reason -> String? in
            let count = missing.count { $0.reason == reason }
            return count > 0 ? "\(count) \(reason.text)" : nil
        }
        lines.append("Records without a USR: \(missing.count) (\(counts.joined(separator: "; "))).")
        lines.append("")
        lines += MarkdownList.lines(missing, header: ["Record", "Reason"], empty: "") { entry in
            [display(entry.record.key, file: entry.record.file, line: entry.record.range.start.line), entry.reason.text]
        }
        return lines
    }

    /// The records with several primary USRs, and the USRs on several
    /// records.
    private static func disagreements(_ listings: [USRListing]) -> [String] {
        let header = ["Kind", "Record", "USR", "Place"]
        return MarkdownList.lines(listings, header: header, empty: "No USR and key disagree.") { listing in
            [
                listing.kind == .severalUSRs ? "several USRs on one record" : "one USR on several records",
                code(listing.key),
                code(listing.usr),
                place(listing)
            ]
        }
    }

    /// The definitions with no record, counted by sub-reason and listed.
    private static func withoutRecord(_ listings: [USRListing]) -> [String] {
        guard listings.isEmpty == false else {
            return ["Every definition the index read has a record."]
        }
        let counts = USRListing.Subreason.allCases.compactMap { subreason -> String? in
            let count = listings.count { $0.subreason == subreason }
            return count > 0 ? "\(count) \(text(subreason))" : nil
        }
        let header = ["Why", "Symbol", "USR", "Place", "Innermost record"]
        return ["Definitions with no record: \(listings.count) (\(counts.joined(separator: "; "))).", ""]
            + MarkdownList.lines(listings, header: header, empty: "") { listing in
                [
                    listing.subreason.map(text) ?? "—",
                    code(listing.name),
                    code(listing.usr),
                    place(listing),
                    code(listing.key)
                ]
            }
    }

    /// The records of key collisions their USRs tell apart.
    private static func collisions(_ listings: [USRListing]) -> [String] {
        let empty = "No key collision to separate."
        return MarkdownList.lines(listings, header: ["Record", "USR", "Place"], empty: empty) { listing in
            [code(listing.key), code(listing.usr), place(listing)]
        }
    }

    /// Why a definition has no record, as the section says it.
    private static func text(_ subreason: USRListing.Subreason) -> String {
        switch subreason {
        case .incompatibleKind:
            "innermost record of another kind"

        case .outsideRecords:
            "outside every record"

        case .requirement:
            "requirement without a body"
        }
    }

    /// `text` as code, or a dash when there is none.
    private static func code(_ text: String?) -> String {
        text.map { "`\($0)`" } ?? "—"
    }

    /// Where a listed definition is: file, line and column.
    private static func place(_ listing: USRListing) -> String {
        "\(listing.file):\(listing.line):\(listing.column)"
    }

    /// A record as the section names it: its key without the module, and
    /// where it starts.
    static func display(_ key: String, file: String, line: Int) -> String {
        MarkdownSignals.display(key, file: file, line: line)
    }
}
