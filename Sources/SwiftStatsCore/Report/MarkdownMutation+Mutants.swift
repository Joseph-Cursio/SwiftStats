//
//  MarkdownMutation+Mutants.swift
//  SwiftStatsCore
//
//  The rest of the report's Mutation section (M6, design §4, §8): the
//  mapped mutants by operator, the limits of the killing tests (kills
//  naming no test, the first failure stopping a mutant's tests), which
//  kills were judged for suspect tests and the suspect tests with why, the
//  tree's files by disposition with the changed test files and the
//  unresolved and unlisted files, the mutants dropped by design per class,
//  and the unmapped mutants by reason with the first of them (all are in
//  the JSON). Results no run made, from a full run that found nothing to
//  test, have no mutants, kills or base to describe: only their files.
//

extension MarkdownMutation {
    /// SwiftMutator keeps at most this many failing tests per mutant.
    private static let namedTestLimit = 20

    /// Everything after the functions by state.
    static func details(_ mutation: MutationReport) -> [String] {
        guard mutation.runs.isEmpty == false else {
            return filesNoRunTested(mutation)
        }
        let mapped = mutation.mutants.filter { [.record, .type, .file].contains($0.place) }
        var lines = ["Mapped mutants by operator:", ""] + operators(mapped)
        lines += ["", killingTests(mapped, runs: mutation.runs)]
        lines += ["", suspects(mapped, runs: mutation.runs), ""] + suspectTests(mutation.suspectTests)
        lines += [""] + files(mutation.files)
        lines += ["", dropped(mutation.dropped)]
        lines += [""] + unmapped(mutation)
        return lines
    }

    /// The mapped mutants per operator, by verdict, by operator name.
    private static func operators(_ mapped: [Mutant]) -> [String] {
        var table = MarkdownTable(header: [
            "Operator", "Scored", "Killed", "Survived", "Timed out", "No coverage", "Not covered", "Build errors"
        ])
        let byOperator = Dictionary(grouping: mapped, by: \.operatorID)
        for name in byOperator.keys.sorted() {
            let counts = MutationCounts(byOperator[name] ?? [])
            table.rows.append([
                name,
                String(MutationFigures(counts).functionScore.scored),
                String(counts.killed),
                String(counts.survived),
                String(counts.timedOut),
                String(counts.noCoverage),
                String(counts.notCovered),
                String(counts.buildErrors)
            ])
        }
        return table.lines(empty: "No mapped mutants.")
    }

    /// How far the killing tests can be trusted: the kills naming no test,
    /// the crash kills among them, and whether the runs stop a mutant's
    /// tests at the first failure.
    private static func killingTests(_ mapped: [Mutant], runs: [MutationRunRecord]) -> String {
        let kills = mapped.filter { $0.verdict == .killed }
        let unnamed = kills.filter(\.killedBy.isEmpty)
        let share = MutationScore.percent(killed: unnamed.count, scored: kills.count)
            .map { " (\(MarkdownNumber.value($0))%)" } ?? ""
        let crashes = unnamed.count(where: \.isCrashKill)
        let stopping = runs.filter(\.stopsAtFirstFailure).map { String($0.ordinal) }
        let first = switch stopping.count {
        case 0:
            "no run stops a mutant's tests at the first failure"

        case runs.count:
            "every run stops a mutant's tests at the first failure, so a kill names at most the first failing test"

        default:
            "run \(stopping.joined(separator: ", ")) stops a mutant's tests at the first failure, so its kills "
                + "name at most the first failing test"
        }
        return "Killing tests: \(unnamed.count) of \(kills.count) kills name no test\(share), \(crashes) of them "
            + "crash kills, which usually name none; \(first); a kill names at most \(namedTestLimit) tests. "
            + "Killing tests are a lower bound."
    }

    /// The suspect-only kills, how many kills by a failing test were judged,
    /// and what each run judged.
    private static func suspects(_ mapped: [Mutant], runs: [MutationRunRecord]) -> String {
        let counts = MutationCounts(mapped)
        let failed = counts.killed - counts.crashKills
        let judged = runs.map { run in
            let what = switch run.suspectsJudged?.value {
            case true:
                "judged control-run, flaky and reach suspects"

            case false:
                "judged only control-run and flaky suspects (its kills name tests in too few files to judge reach)"

            case nil:
                "judged none (its report wasn't read)"
            }
            return "run \(run.ordinal) \(what)"
        }
        return "Suspect-only kills: \(counts.suspectOnly); suspects judged for \(counts.judgedKills) of \(failed) "
            + "kills by a failing test; \(judged.joined(separator: "; "))."
    }

    /// The tests SwiftMutator judged suspect, with why.
    private static func suspectTests(_ tests: [MutationSuspectTest]) -> [String] {
        guard tests.isEmpty == false else {
            return ["No suspect tests."]
        }
        var table = MarkdownTable(header: ["Run", "Test", "File", "Why"])
        for test in tests {
            let why = suspectWhy(test.why, files: test.files, filesWithKills: test.filesWithKills)
            table.rows.append([String(test.run), test.name, test.file ?? "—", why])
        }
        return table.lines(empty: "")
    }

    /// Why a test is suspect, in words: for reach, the files with kills it
    /// fails in (`files`) of those with a kill naming a test
    /// (`filesWithKills`). The weak tests table says it the same way.
    static func suspectWhy(_ reason: SuspectReason, files: Int?, filesWithKills: Int?) -> String {
        switch reason {
        case .reach:
            "reach: fails in \(MarkdownNumber.optional(files)) of \(MarkdownNumber.optional(filesWithKills)) files "
                + "with kills"

        case .controlRun:
            "failed a control run"

        case .flaky:
            "flaky when rerun alone"
        }
    }

    /// The tree's files by disposition, then the unresolved, unlisted and
    /// changed test files.
    private static func files(_ files: [MutationFile]) -> [String] {
        let count = { (disposition: MutationFileDisposition) in files.count { $0.disposition == disposition } }
        var lines = [
            "Files: \(count(.tested)) tested, \(count(.carried)) carried, \(count(.untested)) not mutated (tests, "
                + "excluded files, other packages), \(count(.deleted)) deleted since the base, \(count(.unresolved)) "
                + "unresolved, \(count(.unlisted)) unlisted."
        ]
        lines += listing(
            "Unresolved (changed since the base and not retested, so they have no results)",
            files.filter { $0.disposition == .unresolved }
        )
        lines += listing(
            "Unlisted (changed since the base, but SwiftMutator tested no mutant in them, so their code no test "
                + "ran isn't listed)",
            files.filter { $0.disposition == .unlisted }
        )
        lines += listing(
            "Test files changed since the base (carried verdicts weren't retested against them)",
            files.filter(\.changedTest)
        )
        return lines
    }

    /// The files of results no run made: the production files unlisted,
    /// with why, and the rest not mutated.
    private static func filesNoRunTested(_ mutation: MutationReport) -> [String] {
        let unlisted = mutation.files.filter { $0.disposition == .unlisted }
        let untested = mutation.files.count { $0.disposition == .untested }
        let lines = [
            "Files: \(unlisted.count) unlisted, \(untested) not mutated (tests, excluded files, other packages)."
        ]
        return lines + listing(
            "Unlisted (\(mutation.notListedCause), so their code no test ran isn't listed)",
            unlisted
        )
    }

    /// `files` under `title`, the first of them; nothing when there are none.
    private static func listing(_ title: String, _ files: [MutationFile]) -> [String] {
        guard files.isEmpty == false else {
            return []
        }
        let shown = files.prefix(listedEntries).map { "`\($0.path)`" }.joined(separator: ", ")
        let more = files.count > listedEntries ? "; \(files.count - listedEntries) more in the JSON report" : ""
        return ["", "\(title): \(shown)\(more)."]
    }

    /// The mutants dropped by design, per class.
    private static func dropped(_ dropped: MutationDropped) -> String {
        "Mutants left out by design: \(dropped.build) in build products and dependencies, \(dropped.outsideRoot) "
            + "outside the package, \(dropped.testFiles) in test files, \(dropped.otherPackage) in other packages, "
            + "\(dropped.otherLanguage) not Swift."
    }

    /// The unmapped mutants by reason and the first of them.
    private static func unmapped(_ mutation: MutationReport) -> [String] {
        let entries = mutation.mutants.filter { $0.place == .unmapped }
        guard entries.isEmpty == false else {
            return ["Every mutant in a production file was mapped."]
        }
        let reasons = mutation.unmapped.sorted { $0.key < $1.key }.map { "\($0.value) \($0.key)" }
        var table = MarkdownTable(header: ["File", "Line", "Column", "Operator", "Reason"])
        for entry in entries.prefix(listedEntries) {
            table.rows.append([
                entry.path, String(entry.line), String(entry.column), entry.operatorID, entry.reason ?? "—"
            ])
        }
        var lines = ["Unmapped mutants: \(entries.count) (\(reasons.joined(separator: "; "))).", ""]
        lines += table.lines(empty: "")
        if entries.count > listedEntries {
            lines += ["", "\(entries.count - listedEntries) more in the JSON report."]
        }
        return lines
    }
}
