//
//  RiskMarker.swift
//  SwiftStatsCore
//
//  One risk marker risky + untested judges (PRD §8, M5): a crash marker
//  (a force unwrap, `try!`, `as!` or implicitly unwrapped optional) or a
//  race marker (`@unchecked Sendable`, `nonisolated(unsafe)`), as a finding
//  location attaches it to a function, a type or a file.
//

/// A crash or race marker at one place.
struct RiskMarker: Hashable {
    /// The crash markers, by tool, then rule.
    static let crashRules: [String: Set<String>] = [
        SwiftProjectLintAdapter.name: ["forceCast", "forceTry", "forceUnwrap"],
        MarkerCollector.tool: ["implicitlyUnwrappedOptional"]
    ]
    /// The race markers, all SwiftProjectLint's.
    static let raceRules: Set<String> = ["nonisolatedUnsafe", "uncheckedSendable"]

    /// The tool that found it.
    let tool: String
    /// Its rule.
    let rule: String
    /// Its file.
    let file: String
    /// Its line; nil when the tool gave none.
    let line: Int?
    /// Its column; nil when the tool gave none, as SwiftProjectLint never does.
    let column: Int?
    /// What it attaches to: a function, a type or a file.
    let attachedTo: FindingTarget
    /// The function's key or the type's owner; nil for a file.
    let owner: String?

    /// Whether it marks a data race rather than a crash.
    var isRace: Bool {
        tool == SwiftProjectLintAdapter.name && Self.raceRules.contains(rule)
    }

    /// What it is about: its function, its type, or its file.
    var subject: RiskSubject {
        switch attachedTo {
        case .function, .type:
            RiskSubject(target: attachedTo, name: owner ?? file)

        case .file, .unscanned:
            RiskSubject(target: .file, name: file)
        }
    }

    /// The marker `row` is, when it is a crash or race marker attached
    /// inside the scan; nil otherwise.
    init?(_ row: FindingRow) {
        let isMarker = Self.crashRules[row.tool]?.contains(row.rule) == true
            || (row.tool == SwiftProjectLintAdapter.name && Self.raceRules.contains(row.rule))
        guard isMarker, row.attachedTo != .unscanned else {
            return nil
        }
        tool = row.tool
        rule = row.rule
        file = row.file
        line = row.line
        column = row.column
        attachedTo = row.attachedTo
        owner = row.owner
    }

    /// The markers among `rows`, in their order, one per finding location.
    /// Rows naming the same tool, rule, file, line and column merge only
    /// when the column is known: without one (SwiftProjectLint gives
    /// none), two findings on one line are two markers.
    static func markers(in rows: [FindingRow]) -> [Self] {
        var seen: Set<Self> = []
        var markers: [Self] = []
        for row in rows {
            guard let marker = Self(row) else {
                continue
            }
            guard marker.column != nil else {
                markers.append(marker)
                continue
            }
            if seen.insert(marker).inserted {
                markers.append(marker)
            }
        }
        return markers
    }
}
