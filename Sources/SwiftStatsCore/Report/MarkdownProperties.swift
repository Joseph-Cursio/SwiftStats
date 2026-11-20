//
//  MarkdownProperties.swift
//  SwiftStatsCore
//
//  The report's Property candidates section (PRD §7.11): SwiftInferProperties'
//  suggestions counted by tier in the production and test parts, what the
//  cross-target merge dropped, and every candidate that attaches to no
//  function, listed so none goes missing. When the tool didn't run, the
//  section says why.
//

/// Renders the Property candidates section.
enum MarkdownProperties {
    /// How many characters of a revision to show.
    private static let shortRevisionLength = 10
    /// The tiers SwiftInferProperties writes, in report order.
    private static let tiers = ["Strong", "Likely", "Possible", "Advisory"]

    /// The section's lines after its heading.
    static func render(_ scan: ScanReport) -> [String] {
        guard let properties = scan.properties else {
            let status = scan.collectors.first { $0.name == SwiftInferPropertiesAdapter.name }
            let why = status.map { status in
                status.state.rawValue + (status.reason.map { ", \($0)" } ?? "")
            }
            return ["Not collected: \(why ?? "not in this snapshot")."]
        }
        let candidates = properties.candidates
        let unmapped = candidates.filter { $0.unmapped != nil }
        let revision = properties.seiRevision.map { revision in
            "\(revision.prefix(shortRevisionLength)) (possibly stale after a resolve without a rebuild)."
        }
        var lines = [
            "SwiftInferProperties' suggestions, indexed per target and merged: "
                + "\(counted(candidates.count, "candidate", "candidates")), "
                + "\(candidates.count - unmapped.count) attached to a function and \(unmapped.count) not. "
                + "The merge dropped \(counted(properties.crossTargetDuplicates, "duplicate", "duplicates")) "
                + "and \(counted(properties.crossTargetConflicts, "conflicting row", "conflicting rows")); "
                + "\(counted(properties.identityCollisions, "identity", "identities")) at more than one location.",
            "swift-infer's SwiftEffectInference: "
                + (revision ?? "unknown (the binary isn't in a SwiftPM build directory).")
        ]
        lines += [""] + tierTable(scan, candidates: candidates)
        if unmapped.isEmpty == false {
            lines += ["", "Not attached to a function:", ""] + unmappedTable(unmapped)
        }
        return lines
    }

    /// Candidates by tier in the production and test parts.
    private static func tierTable(_ scan: ScanReport, candidates: [PropertyCandidate]) -> [String] {
        let part = { (name: String) in
            scan.rollups.first { $0.scope == .project && $0.name == name }?.properties?.tier ?? [:]
        }
        let production = part("production")
        let tests = part("tests")
        let others = Set(candidates.map(\.tier)).subtracting(tiers).sorted()
        let table = MarkdownTable(
            header: ["Tier", "Production", "Tests"],
            rows: (tiers + others).map { tier in
                [tier, String(production[tier, default: 0]), String(tests[tier, default: 0])]
            }
        )
        return table.lines(empty: "")
    }

    /// One row per candidate in `unmapped`, in report order.
    private static func unmappedTable(_ unmapped: [PropertyCandidate]) -> [String] {
        let table = MarkdownTable(
            header: ["Identity", "Template", "Tier", "Function", "Location", "Why"],
            rows: unmapped.map { candidate in
                [
                    candidate.identity,
                    candidate.template,
                    candidate.tier,
                    candidate.function,
                    candidate.location.map { location in
                        location.line.map { "\(location.file):\($0)" } ?? location.file
                    } ?? "none",
                    candidate.unmapped.map(reason(_:)) ?? ""
                ]
            }
        )
        return table.lines(empty: "")
    }

    /// Why a candidate attaches to no function, in words.
    private static func reason(_ unmapped: PropertyCandidate.Unmapped) -> String {
        switch unmapped {
        case .file:
            return "in a scanned file, outside any type or function"

        case .missingLocation:
            return "no location in the package"

        case .type:
            return "inside a type, outside any function"

        case .unscanned:
            return "in a file the scan didn't cover"
        }
    }

    /// `count` with the noun in the singular for one.
    private static func counted(_ count: Int, _ singular: String, _ plural: String) -> String {
        "\(count) \(count == 1 ? singular : plural)"
    }
}
