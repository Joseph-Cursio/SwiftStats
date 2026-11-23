//
//  MarkdownSignals.swift
//  SwiftStatsCore
//
//  The signals and history sections of a Markdown report, and `top`'s
//  table (PRD §8, §10). A signal shows its first members and how many it
//  has; one left out says why. The history section says what the numbers
//  rest on: the window, the merge style, and which commits counted as
//  fixes, reverts and sweeps.
//

/// Renders signals and history as Markdown.
public enum MarkdownSignals {
    /// Members a report lists per signal.
    static let reportedMembers = 10
    /// Items `top` shows when not told how many.
    public static let defaultTopLimit = 20
    /// Coupled pairs a report lists.
    static let reportedPairs = 10
    /// Characters of a commit hash or date a report shows.
    static let shortLength = 10

    /// The signals section's lines, after its heading. What the history
    /// numbers rest on heads the first signal computed from history.
    static func render(_ signals: [SignalResult], history: HistoryReport?) -> [String] {
        var lines: [String] = []
        var source = history.map(Self.source)
        for signal in signals {
            if let header = source, signal.name.requirements.contains(.history) {
                lines += header
                source = nil
            }
            lines += ["", "### \(signal.name.title)", ""]
            if let reason = signal.leftOut {
                lines.append("Left out: \(reason).")
                continue
            }
            let members = signal.members
            lines.append("\(members.count) members (\(signal.rule)).")
            guard members.isEmpty == false else {
                continue
            }
            lines.append("")
            lines += table(Array(members.prefix(reportedMembers)), signal: signal.name)
            if members.count > reportedMembers {
                let limit = members.count > defaultTopLimit ? " --limit \(members.count)" : ""
                let command = "swiftstats top \(signal.name.rawValue)\(limit)"
                lines += ["", "\(members.count - reportedMembers) more: `\(command)`."]
            }
        }
        return lines
    }

    /// `top`'s output: the ranked items, members marked.
    public static func top(_ signal: SignalResult, limit: Int) -> String {
        var lines = ["# \(signal.name.title)", ""]
        if let reason = signal.leftOut {
            lines.append("Left out: \(reason).")
            return lines.joined(separator: "\n") + "\n"
        }
        let members = signal.members.count
        let shown = Array(signal.items.prefix(limit))
        lines.append("\(members) members of \(signal.items.count) ranked (\(signal.rule)); showing \(shown.count).")
        if shown.isEmpty == false {
            lines.append("")
            lines += table(shown, signal: signal.name, markMembers: true)
        }
        return lines.joined(separator: "\n") + "\n"
    }

    /// The history section's lines, after its heading.
    static func history(_ history: HistoryReport) -> [String] {
        var lines = [
            "\(history.windowCommits) of \(history.commits) commits fall in the window (from \(history.windowStart)); "
                + "the repository merges by \(history.mergeStyle.rawValue)."
        ]
        lines += notes("Fix commits", history.fixCommits)
        lines += notes("Reverts", history.revertCommits)
        lines += notes("Sweeps (left out of churn, fixes and coupling)", history.sweepCommits)
        lines += ["", "### Change coupling", ""]
        var table = MarkdownTable(header: ["Family", "Changes with", "Together", "Changes"])
        for pair in history.coupling.prefix(reportedPairs) {
            table.rows.append([
                display(pair.familyA, file: pair.fileA),
                display(pair.familyB, file: pair.fileB),
                String(pair.support),
                "\(pair.changesA) / \(pair.changesB)"
            ])
        }
        lines += table.lines(empty: "No pairs changed together often enough.")
        if history.warnings.isEmpty == false {
            lines += ["", "Warnings:", ""] + history.warnings.map { "- \($0)" }
        }
        return lines
    }

    /// What the history signals rest on: the history read and, for a
    /// squashing repository, that it is coarse.
    private static func source(_ history: HistoryReport) -> [String] {
        let source = "From the history of \(history.commit.prefix(shortLength)) over the "
            + "\(history.windowDays) days to \(history.date); "
            + "thresholds come from the configuration the report was made with."
        var lines = ["", source]
        if history.mergeStyle == .squash {
            let coarse = "This repository squashes its merges, so each branch counts as one commit and the "
                + "history is coarse."
            lines += ["", coarse]
        }
        return lines
    }

    /// A list of commit notes under `title`.
    private static func notes(_ title: String, _ notes: [HistoryCommitNote]) -> [String] {
        var lines = ["", "### \(title)", ""]
        var table = MarkdownTable(header: ["Commit", "Date", "Subject", "Files", "Families", "Counted"])
        for note in notes {
            table.rows.append([
                String(note.commit.prefix(shortLength)),
                String(note.date.prefix(shortLength)),
                note.subject,
                String(note.files),
                String(note.families),
                note.excluded.map { "no: \($0)" } ?? "yes"
            ])
        }
        lines += table.lines(empty: "None in the window.")
        return lines
    }

    /// A table of signal items with the inputs `signal` uses.
    private static func table(_ items: [SignalItem], signal: SignalName, markMembers: Bool = false) -> [String] {
        let inputs = columns(for: signal)
        var header = ["#", subjectHeading(for: signal), "Score"] + inputs.map(\.0)
        if markMembers {
            header.append("Member")
        }
        var table = MarkdownTable(header: header)
        for item in items {
            var row = [
                String(item.rank),
                display(item.subject, file: item.file, line: item.line),
                MarkdownNumber.value(item.score)
            ]
            row += inputs.map { $0.1(item) }
            if markMembers {
                row.append(item.member ? "yes" : "no")
            }
            table.rows.append(row)
        }
        return table.lines(empty: "")
    }

    /// The input columns of `signal`'s table, after the score: headings,
    /// and how each cell reads an item.
    private static func columns(for signal: SignalName) -> [(String, (SignalItem) -> String)] {
        let traced = ("Traced by", history { $0.tracedBy.rawValue })
        return switch signal {
        case .bugProne:
            [
                ("Fixes (window / all)", history { "\($0.fixes) / \($0.allFixes)" }),
                ("Changes", history { String($0.changes) }),
                traced
            ]

        case .hotspot:
            [
                ("Changes", history { String($0.changes) }),
                ("Cognitive", history { MarkdownNumber.optional($0.cognitive) }),
                traced
            ]

        case .safeToLeave:
            [
                ("Cognitive", history { MarkdownNumber.optional($0.cognitive) }),
                ("First seen", history { String(($0.firstSeen ?? "—").prefix(shortLength)) }),
                traced
            ]

        case .testsNotKeepingUp:
            [
                ("Changes", history { String($0.changes) }),
                ("With a test change", history { String($0.testChanges) }),
                traced
            ]

        case .unstableFixes:
            [
                ("Reverts", history { String($0.reverts) }),
                ("Repeated fixes", history { String($0.repeatedFixes) }),
                traced
            ]

        case .cloneHotspot, .divergentClones, .missingTemplate, .riskyUntested, .toolDisagreement, .uncheckedLaws,
            .unevenCloneTesting, .untestedProperty:
            m4Columns(for: signal)

        case .bestPropertyTarget, .genuinelyUnderTested, .unevenCloneMutation, .weakTests:
            mutationColumns(for: signal)
        }
    }

    /// What the subject column of `signal`'s table heads: a type for
    /// unchecked laws, a copy or class for the clone signals, a function,
    /// type or file for risky + untested, else a function.
    private static func subjectHeading(for signal: SignalName) -> String {
        switch signal {
        case .cloneHotspot:
            "Class (first copy)"

        case .divergentClones:
            "Unchanged copy"

        case .riskyUntested:
            "Function, type or file"

        case .unevenCloneTesting:
            "Least covered copy"

        case .unevenCloneMutation:
            "Least killed copy"

        case .uncheckedLaws:
            "Type"

        default:
            "Function"
        }
    }

    /// A cell reading an item's history payload with `cell`; a dash
    /// without one.
    private static func history(_ cell: @escaping (SignalItem.History) -> String) -> (SignalItem) -> String {
        { item in item.history.map(cell) ?? "—" }
    }

    /// A family as a report names it: its key without the module, and where it is.
    static func display(_ family: String, file: String) -> String {
        display(family, file: file, line: nil)
    }

    /// A family as a report names it, with the line it starts on when known.
    static func display(_ family: String, file: String, line: Int?) -> String {
        let place = line.map { "\(file):\($0)" } ?? file
        return "`\(HistoryMatcher.stripModule(KeyForm.withoutFile(family, file: file)))` (\(place))"
    }
}
