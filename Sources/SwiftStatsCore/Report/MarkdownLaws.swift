//
//  MarkdownLaws.swift
//  SwiftStatsCore
//
//  The report's Law checks section (PRD §7.11): production conformances to
//  the protocols SwiftPropertyLaws checks, counted by state, never one line
//  per pair, with what couldn't be attached and whether the package
//  depends on the kit.
//

/// Renders the Law checks section.
enum MarkdownLaws {
    /// The section's lines after its heading: the production part's counts,
    /// or why there are none.
    static func render(_ scan: ScanReport) -> [String] {
        let production = scan.rollups.first { $0.scope == .project && $0.name == "production" }
        guard let counts = production?.laws else {
            return ["No production code."]
        }
        let laws = scan.laws
        let dependency = laws.kitDependency ? "depends" : "does not depend"
        var lines = [
            "Production conformances to the protocols SwiftPropertyLaws checks. "
                + "The package \(dependency) on SwiftPropertyLaws."
        ]
        let table = MarkdownTable(
            header: ["State", "Pairs"],
            rows: LawCheck.State.allCases.map { state in
                [state.rawValue, String(counts.state[state.rawValue, default: 0])]
            }
        )
        lines += [""] + table.lines(empty: "")
        lines += [
            "",
            "\(counted(laws.unresolvedCalls, "check call", "check calls")) with no subject SwiftStats can name; "
                + "\(counted(laws.ambiguousNames.count, "ambiguous type name", "ambiguous type names")); "
                + "\(counted(laws.testOnlyConformances, "conformance", "conformances")) only test targets declare."
        ]
        return lines
    }

    /// `count` with the noun in the singular for one.
    private static func counted(_ count: Int, _ singular: String, _ plural: String) -> String {
        "\(count) \(count == 1 ? singular : plural)"
    }
}
