//
//  MarkdownIndex+Warnings.swift
//  SwiftStatsCore
//
//  The compiler-warning part of the report's Build and index section (M7,
//  design §6.3, §10.1): the `swiftc` findings by diagnostic ID and group,
//  with each ID's count and first message, the first 20 places, a note on
//  `bridged_warning` (the generic ID of macros' diagnostics), the warnings
//  in plugin targets apart, and the warnings dropped or left unmapped;
//  when there are none, "No compiler warnings" with the dropped count,
//  or, when some were left unmapped, "No compiler warnings mapped to the
//  package" with the dropped and unmapped counts.
//

extension MarkdownIndex {
    /// The warning places the section lists.
    static let listedPlaces = 20
    /// The diagnostic ID the compiler gives macros' warnings.
    static let bridgedWarning = "bridged_warning"

    /// The section's compiler-warning part.
    static func warnings(_ scan: ScanReport, build: BuildReport) -> [String] {
        let warnings = scan.findings.filter { $0.tool == WarningReader.tool }
        let dropped = "\(build.warningsDropped) dropped (under the build directory or outside the package root)"
        let unmapped = "\(build.warningsUnmapped) unmapped (in a macro expansion without its origin, at an unknown "
            + "place, or in a file changed during the scan)"
        guard warnings.isEmpty == false else {
            guard build.warningsUnmapped == 0 else {
                return ["No compiler warnings mapped to the package; \(dropped); \(unmapped)."]
            }
            return ["No compiler warnings; \(dropped)."]
        }
        var lines = ["\(warnings.count) compiler warnings, by diagnostic ID and group:", ""] + byIdentifier(warnings)
        if warnings.contains(where: { $0.rule == bridgedWarning }) {
            let note = "`\(bridgedWarning)` is the ID the compiler gives warnings raised in macro expansions "
                + "(Swift Testing's `#expect` and `#require` among them), whatever their kind."
            lines += ["", note]
        }
        lines += ["", "First places:", ""]
        let header = ["Place", "ID", "Message"]
        lines += MarkdownList.lines(warnings, limit: listedPlaces, header: header, empty: "") { warning in
            [place(warning), warning.rule, warning.message]
        }
        return lines + ["", "In plugin targets: \(build.pluginWarnings). Also \(dropped); \(unmapped)."]
    }

    /// One row per diagnostic ID and group: the count and the first
    /// message, most frequent first.
    private static func byIdentifier(_ warnings: [Finding]) -> [String] {
        let groups = Dictionary(grouping: warnings) { "\($0.rule)\u{0}\($0.category ?? "")" }
        let ordered = groups.values.sorted { lhs, rhs in
            guard lhs.count == rhs.count, let left = lhs.first, let right = rhs.first else {
                return lhs.count > rhs.count
            }
            return (left.rule, left.category ?? "") < (right.rule, right.category ?? "")
        }
        var table = MarkdownTable(header: ["ID", "Group", "Count", "First message"])
        for group in ordered {
            guard let first = group.first else {
                continue
            }
            table.rows.append([first.rule, first.category ?? "—", String(group.count), first.message])
        }
        return table.lines(empty: "")
    }

    /// Where a warning is: its first location's file and line.
    private static func place(_ warning: Finding) -> String {
        guard let location = warning.locations.first else {
            return "—"
        }
        return location.file + (location.line.map { ":\($0)" } ?? "")
    }
}
