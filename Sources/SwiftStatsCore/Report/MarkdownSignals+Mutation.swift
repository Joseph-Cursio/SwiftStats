//
//  MarkdownSignals+Mutation.swift
//  SwiftStatsCore
//
//  The input columns of M6's signal tables (design §7, §8): for weak tests
//  the function score, the lines covered, the first survivors, the suspect
//  tests with why, how many tests kill its mutants with the first of them,
//  and the module's test-to-code lines; for genuinely under-tested the
//  function score, the lines covered and the module's test-to-code lines
//  against the project's; for best property-test target the suggestions
//  with their flags, the first unkilled mutants and the partners; for
//  uneven clone testing's mutation part each measured copy's mutants killed
//  of scored and ran unchecked against never ran, with the class. A cell
//  whose payload is absent shows a dash.
//

extension MarkdownSignals {
    /// Survivors and unkilled mutants a cell names before saying how many
    /// more there are.
    static let listedMutants = 3

    /// Weak tests: the function score and lines covered, then what the
    /// tests run without checking and who checks the rest.
    static var weakTestsColumns: [Column] {
        [
            ("Function score", mutation { functionScore($0.functionScore) }),
            ("Lines covered", coverage { tally($0.lines) }),
            ("Survivors", mutation { mutants($0.survivors) }),
            ("Suspect tests", mutation(suspects)),
            ("Killing tests", mutation(killingTests)),
            ("Module test / production lines", ratio { lines($0.moduleLines) })
        ]
    }

    /// Genuinely under-tested: the function score, lines covered, and the
    /// module's test code against the project's.
    static var genuinelyUnderTestedColumns: [Column] {
        [
            ("Function score", mutation { functionScore($0.functionScore) }),
            ("Lines covered", coverage { tally($0.lines) }),
            ("Module vs project test / production lines", ratio { ratio in
                "\(lines(ratio.moduleLines)) vs \(lines(ratio.projectLines))"
            })
        ]
    }

    /// Best property-test target: the suggestions, the mutants the tests
    /// don't kill, and the partners' share of the score.
    static var bestPropertyTargetColumns: [Column] {
        [
            ("Suggestions", target { $0.suggestions.map(suggestion).joined(separator: "; ") }),
            ("Unkilled", target { mutants($0.unkilled) }),
            ("Partners", target(partners))
        ]
    }

    /// Uneven clone testing (mutation): each measured copy's kills, what
    /// its unkilled mutants are, and the class.
    static var unevenCloneMutationColumns: [Column] {
        [
            ("Copies killed", cloneMutation { $0.copies.map(killedCopy).joined(separator: "; ") }),
            ("Ran unchecked / never ran", cloneMutation { mutation in
                mutation.copies.map { "\($0.runButUnchecked) / \($0.unrun)" }.joined(separator: "; ")
            }),
            ("Kind", clone(kind)),
            ("Mass", clone { String($0.mass) }),
            ("Folded", cloneMutation { $0.folded.isEmpty ? "—" : $0.folded.map { "#\($0)" }.joined(separator: ", ") })
        ]
    }

    /// The input columns of M6's signal `signal`; none for the others.
    static func mutationColumns(for signal: SignalName) -> [Column] {
        switch signal {
        case .weakTests:
            weakTestsColumns

        case .genuinelyUnderTested:
            genuinelyUnderTestedColumns

        case .bestPropertyTarget:
            bestPropertyTargetColumns

        case .unevenCloneMutation:
            unevenCloneMutationColumns

        default:
            []
        }
    }

    /// Killed of scored, with the percentage; a dash when nothing was
    /// scored.
    private static func functionScore(_ score: MutationScore) -> String {
        guard let percent = score.percent else {
            return "—"
        }
        return "\(score.killed)/\(score.scored) (\(MarkdownNumber.value(percent))%)"
    }

    /// The first mutants as `Operator@line`, and how many more there are; a
    /// dash for none.
    private static func mutants(_ mutants: [UncheckedMutant]) -> String {
        guard mutants.isEmpty == false else {
            return "—"
        }
        let named = mutants.prefix(listedMutants).map { "\($0.operatorID)@\($0.line)" }.joined(separator: ", ")
        return named + (mutants.count > listedMutants ? " (+\(mutants.count - listedMutants) more)" : "")
    }

    /// The suspect tests behind the suspect-only kills, with why in the
    /// Mutation section's words (a reason it doesn't know as written); a
    /// dash for none.
    private static func suspects(_ mutation: SignalItem.Mutation) -> String {
        guard mutation.suspects.isEmpty == false else {
            return "—"
        }
        return mutation.suspects.map { suspect in
            let why = SuspectReason(rawValue: suspect.why).map { reason in
                MarkdownMutation.suspectWhy(reason, files: suspect.files, filesWithKills: suspect.filesWithKills)
            }
            return "\(suspect.name) (\(why ?? suspect.why))"
        }
        .joined(separator: "; ")
    }

    /// How many tests the kills name, and the first of them (Swift
    /// Testing's display names can be sentences; the JSON names five).
    private static func killingTests(_ mutation: SignalItem.Mutation) -> String {
        guard let first = mutation.firstKillingTests.first else {
            return String(mutation.killingTests)
        }
        return "\(mutation.killingTests): \(first)" + (mutation.killingTests > 1 ? ", …" : "")
    }

    /// Test lines of production lines; a dash when unmeasured.
    private static func lines(_ lines: SignalItem.RatioLines?) -> String {
        lines.map { "\($0.testLines)/\($0.productionLines)" } ?? "—"
    }

    /// A suggestion: its template and tier, flagged when Verified, blocked
    /// or already tested by a property test.
    private static func suggestion(_ property: SignalItem.Property) -> String {
        var flags = [property.tier]
        if property.verified {
            flags.append("verified")
        }
        if property.blocked {
            flags.append("blocked")
        }
        if let link = property.testedBy {
            flags.append("tested (\(link.rawValue))")
        }
        return "\(property.template) (\(flags.joined(separator: ", ")))"
    }

    /// The partners of the two-function suggestions, each with its unkilled
    /// mutants; a dash for none.
    private static func partners(_ target: SignalItem.PropertyTarget) -> String {
        guard target.partners.isEmpty == false else {
            return "—"
        }
        return target.partners
            .map { "`\(HistoryMatcher.stripModule($0.key))`: \($0.unkilled.count) unkilled" }
            .joined(separator: "; ")
    }

    /// A copy: its family and its mutants killed of scored.
    private static func killedCopy(_ copy: SignalItem.MutatedCopy) -> String {
        "\(display(copy.family, file: copy.file, line: copy.line)): \(copy.killed)/\(copy.scored)"
    }

    /// A cell reading an item's mutation results with `cell`.
    private static func mutation(_ cell: @escaping (SignalItem.Mutation) -> String) -> (SignalItem) -> String {
        { item in item.mutation.map(cell) ?? "—" }
    }

    /// A cell reading an item's test-to-code line ratios with `cell`.
    private static func ratio(_ cell: @escaping (SignalItem.Ratio) -> String) -> (SignalItem) -> String {
        { item in item.ratio.map(cell) ?? "—" }
    }

    /// A cell reading an item's property-test target with `cell`.
    private static func target(_ cell: @escaping (SignalItem.PropertyTarget) -> String) -> (SignalItem) -> String {
        { item in item.propertyTarget.map(cell) ?? "—" }
    }

    /// A cell reading an item's clone mutation results with `cell`.
    private static func cloneMutation(
        _ cell: @escaping (SignalItem.CloneMutation) -> String
    ) -> (SignalItem) -> String {
        { item in item.clone?.mutation.map(cell) ?? "—" }
    }
}
