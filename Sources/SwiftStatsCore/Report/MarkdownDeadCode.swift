//
//  MarkdownDeadCode.swift
//  SwiftStatsCore
//
//  The report's Dead code section (M7, design §5, §7, §10.1), read only
//  from stored facts (no run times): the `periphery` collector's status
//  with a carry's date apart, outskirts' version and build (`sha256:` and
//  10 hex digits, with its label), the two runs and their result counts,
//  the retained public modules, then the unused production declarations
//  by kind and the other hints, the dead records and the test-to-code
//  ratio both ways per production module, the results left out per class,
//  the unused production declarations themselves (at most 50; the JSON
//  lists all) and outskirts' known limits. When outskirts didn't run, the
//  section says why, and when that status was carried from an earlier scan
//  of the same tree, from when.
//

/// Renders the Dead code section.
enum MarkdownDeadCode {
    /// Characters of outskirts' build hash shown after `sha256:`.
    private static let shortHashLength = 10
    /// What starts a build's identity.
    private static let hashPrefix = "sha256:"
    /// What outskirts' known limits are (design §5.6), as the section
    /// lists them.
    private static let limits = [
        "An unused import of a module whose types appear only in the signatures of functions the file calls is "
            + "missed.",
        "A declaration called only from an inactive `#if` branch is reported unused, so dead but tested can list "
            + "a function whose only caller this build doesn't compile.",
        "A non-test helper target used only by tests is analysed as production code.",
        "Unused parameters of a parameterized `@Test` in a file that sees `Testing` only through a re-export are "
            + "reported (test-target results are left out anyway).",
        "Unused local variables come back as unused globals once locals are indexed; SwiftStats classes them local "
            + "and leaves them out."
    ]

    /// The section's lines after its heading; `runs` are the snapshot's
    /// collector runs, which hold outskirts' build.
    static func render(_ scan: ScanReport, runs: [CollectorRunInfo]) -> [String] {
        let status = scan.collectors.first { $0.name == PeripheryAdapter.name }
        let carried = MarkdownCarry.lines(carried: MarkdownCarry.carried(status))
        guard let dead = scan.deadCode else {
            return ["Not collected: \(MarkdownCarry.state(status))."] + carried
        }
        var lines = ["Status: \(MarkdownCarry.state(status))."] + carried
        lines.append(tool(dead, run: runs.first { $0.name == PeripheryAdapter.name }))
        let results = DeadCodeRun.ordered.map { run in
            "\(run.rawValue) \(dead.runs.first { $0.name == run }?.results ?? 0)"
        }
        lines.append("Results per run (roots: test targets are roots; production: they aren't): "
            + results.joined(separator: ", ") + ".")
        let retained = status?.options.first { $0.hasPrefix(PeripheryCommand.retainOptionLead) }
            .map { String($0.dropFirst(PeripheryCommand.retainOptionLead.count)) }
        lines.append("Retained public modules: \(retained ?? "not recorded").")
        lines += ["", "### Unused declarations", ""] + declarations(dead)
        lines += ["", "### Dead records and the test-to-code ratio", ""] + ratios(scan)
        lines += ["", "Results left out, per class:", ""] + dropped(dead)
        lines += ["", "### outskirts' limits", ""] + limits.map { "- \($0)" }
        return lines
    }

    /// outskirts' version, build and label.
    private static func tool(_ dead: DeadCodeReport, run: CollectorRunInfo?) -> String {
        let build = run?.identity.map { identity in
            identity.hasPrefix(hashPrefix)
                ? hashPrefix + identity.dropFirst(hashPrefix.count).prefix(shortHashLength)
                : identity
        }
        let label = run?.identityLabel.map { " (\($0))" } ?? ""
        return "outskirts \(dead.version), build \(build ?? "not recorded")\(label)."
    }

    /// The unused production declarations by kind per run, the other hints
    /// and the declarations themselves.
    private static func declarations(_ dead: DeadCodeReport) -> [String] {
        let unused = dead.declarations.filter(\.isUnusedProduction)
        var table = MarkdownTable(header: ["Kind", "Roots run", "Production run"])
        for kind in DeadCodeRollup.kinds {
            let counts = DeadCodeRun.ordered.map { run in
                unused.count { $0.run == run && DeadCodeRollup.kind(of: $0.kind) == kind }
            }
            table.rows.append([kind] + counts.map(String.init))
        }
        var lines = ["Unused production declarations by kind:", ""] + table.lines(empty: "")
        lines += ["", hints(dead)]
        let covered = Dictionary(grouping: dead.records) { "\($0.run.rawValue)#\($0.declaration)" }
        let header = ["Run", "Kind", "Name", "Place", "Via", "Records covered"]
        lines += ["", "Unused production declarations:", ""]
        lines += MarkdownList.lines(unused, header: header, empty: "No unused production declarations.") { entry in
            let records = covered["\(entry.run.rawValue)#\(entry.ordinal)", default: []]
            let vias = Set(records.map(\.via.rawValue)).sorted()
            return [
                entry.run.rawValue,
                entry.kind,
                "`\(entry.name)`",
                entry.file.map { "\($0):\(entry.line)" } ?? "outside the package",
                vias.isEmpty ? "—" : vias.joined(separator: ", "),
                String(records.count)
            ]
        }
        return lines
    }

    /// The production results with a hint other than unused, by run and
    /// hint.
    private static func hints(_ dead: DeadCodeReport) -> String {
        let others = dead.declarations.filter { $0.entryClass == .production && $0.hint != DeadCodeMapper.unusedHint }
        guard others.isEmpty == false else {
            return "No other hints."
        }
        let parts = DeadCodeRun.ordered.compactMap { run -> String? in
            let counts = Dictionary(grouping: others.filter { $0.run == run }, by: \.hint)
            guard counts.isEmpty == false else {
                return nil
            }
            let named = counts.keys.sorted().map { "\(counts[$0]?.count ?? 0) \($0)" }
            return "\(run.rawValue) run " + named.joined(separator: ", ")
        }
        return "Other hints: " + parts.joined(separator: "; ") + "."
    }

    /// The dead records, dead lines and line ratios of the production part
    /// and each production module.
    private static func ratios(_ scan: ScanReport) -> [String] {
        let project = scan.rollups.filter { $0.scope == .project && $0.deadCode != nil }
        let modules = scan.rollups.filter { $0.scope == .module && $0.deadCode != nil }.sorted { $0.name < $1.name }
        var table = MarkdownTable(header: [
            "", "Dead with tests as roots", "Production-dead", "Dead lines", "Test / production",
            "Test / (production − dead)", "Unused declarations without a line count"
        ])
        for rollup in project + modules {
            guard let counts = rollup.deadCode else {
                continue
            }
            let ratio = rollup.tests.lineRatio
            let live = ratio.deadLines.map { ratio.productionLines - $0 }
            table.rows.append([
                rollup.name,
                String(counts.records),
                String(counts.productionRecords),
                MarkdownNumber.optional(ratio.deadLines),
                share(ratio.testLines, of: ratio.productionLines),
                live.map { share(ratio.testLines, of: $0) } ?? "—",
                String(counts.unsized)
            ])
        }
        let note = "Records are function records; dead lines are the stripped lines of the outermost declarations the "
            + "roots run finds unused."
        return table.lines(empty: "No production code.") + ["", note]
    }

    /// The results left out of the mapping, per run and class.
    private static func dropped(_ dead: DeadCodeReport) -> [String] {
        var table = MarkdownTable(header: [
            "Run", "Test targets", "Local declarations", "Outside the package", "Under the build directory",
            "Unscanned files", "Files changed during the scan"
        ])
        for run in DeadCodeRun.ordered {
            guard let counts = dead.dropped[run.rawValue] else {
                continue
            }
            table.rows.append([run.rawValue] + [
                counts.test, counts.local, counts.outsideRoot, counts.build, counts.unscanned, counts.fileChanged
            ].map(String.init))
        }
        return table.lines(empty: "Nothing left out.")
    }

    /// `part` lines per `whole` line, to two places; a dash for no lines.
    private static func share(_ part: Int, of whole: Int) -> String {
        guard whole > 0 else {
            return "—"
        }
        return MarkdownNumber.value(Double(part) / Double(whole))
    }
}
