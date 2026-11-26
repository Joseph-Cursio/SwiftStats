//
//  SuspectReport.swift
//  SwiftStatsCore
//
//  Suspect-only kills (M6, design §2, U4), from `swift-mutator report -f
//  json`: results.jsonl doesn't record them. Each applied operator's `key`
//  is read into the full five-part key (`MutantKey(spelled:)`); entries
//  with no key, the placeholders of files without coverage, are skipped.
//  The join is one to one: a kill whose key no readable entry has (its
//  entry's key doesn't read, or SwiftMutator's stricter reader skipped its
//  results line) is unjudged, whatever the summary says, and counted in a
//  warning. SwiftMutator writes `killedOnlyBySuspectTests` only as true, so a flag
//  present is true; an absent one is false when the summary says suspects
//  were checked, and unjudged (nil) when it says they weren't or there is
//  no summary, since the reach rule then didn't run. Only a kill by a
//  failed test can be suspect-only. The suspect tests come from the
//  summary's `tests`, each with why it is suspect.
//

import Foundation

/// The suspect flags and tests of a SwiftMutator JSON report.
struct SuspectReport: Equatable, Sendable {
    /// A test SwiftMutator judged suspect, and why.
    struct SuspectTest: Equatable, Sendable {
        /// Its name, as SwiftMutator records it.
        let name: String
        /// Its file, when SwiftMutator knows it.
        let file: String?
        /// Why it is suspect.
        let reason: SuspectReason
        /// For `reach`: how many files with kills it failed in.
        let files: Int?
        /// For `reach`: how many files have a kill naming a test.
        let filesWithKills: Int?
    }

    /// The report's shape, as far as it is read.
    private struct Document: Decodable {
        /// The files' mutants.
        let fileReports: [FileReport]
        /// The summary; absent from an older report.
        let killingTestSummary: Summary?
    }

    /// A file's mutants.
    private struct FileReport: Decodable {
        /// Its mutants.
        let appliedOperators: [Applied]
    }

    /// A mutant of the report.
    private struct Applied: Decodable {
        /// Its spelled key; absent on a placeholder.
        let key: String?
        /// True when only suspect tests killed it; SwiftMutator writes it
        /// only as true.
        let killedOnlyBySuspectTests: JSONFlag?
    }

    /// The killing-test summary.
    private struct Summary: Decodable {
        /// Whether enough files have kills for reach to be judged.
        let suspectsChecked: Bool
        /// How many files have a kill naming a test.
        let filesWithKills: Int?
        /// The tests shown, every suspect one among them.
        let tests: [Test]

        /// Reads the summary.
        init(from decoder: any Decoder) throws {
            let container = try decoder.container(keyedBy: JSONKey.self)
            suspectsChecked = try container.decode(Bool.self, forKey: "suspectsChecked")
            filesWithKills = try container.decodeIfPresent(Int.self, forKey: "filesWithKills")
            tests = try container.decodeIfPresent([Test].self, forKey: "tests") ?? []
        }
    }

    /// A test of the summary.
    private struct Test: Decodable {
        /// Its name.
        let name: String
        /// Its file.
        let file: String?
        /// Whether it is suspect.
        let suspect: JSONFlag?
        /// Control runs it failed.
        let failedControlRuns: Int?
        /// Times it didn't fail again alone.
        let notReproducedAlone: Int?
        /// Times it failed again alone.
        let failedAgainAlone: Int?
        /// Files with kills it failed in.
        let files: Int?
    }

    /// How many times a test must fail again alone for each time it
    /// didn't, for that time to count as chance (SwiftMutator's
    /// `failuresAlonePerExemption`).
    static let failuresAlonePerExemption = 4

    /// A report that judged nothing: every flag unjudged.
    static let unjudged = Self(
        flagged: [],
        reported: [],
        suspectsChecked: false,
        suspectTests: [],
        unreadableKeys: 0,
        read: false
    )

    /// The keys flagged suspect-only.
    let flagged: Set<MutantKey>
    /// Every key an entry has that reads, flagged or not: the mutants the
    /// report can judge.
    let reported: Set<MutantKey>
    /// Whether suspects were checked; false when the report has no
    /// summary.
    let suspectsChecked: Bool
    /// The suspect tests, sorted by name, then file.
    let suspectTests: [SuspectTest]
    /// How many entries had a key that didn't read.
    let unreadableKeys: Int
    /// Whether a report was read; false for one that wasn't run, failed or
    /// didn't decode, which judged nothing.
    let read: Bool

    /// The report in `data`; a `MutationFailure` when it doesn't decode.
    static func decode(_ data: Data) throws(MutationFailure) -> Self {
        let document: Document
        do {
            document = try JSONDecoder().decode(Document.self, from: data)
        } catch {
            throw MutationFailure(description: "`swift-mutator report`'s JSON doesn't read")
        }
        var flaggedKeys = Set<MutantKey>()
        var reportedKeys = Set<MutantKey>()
        var unreadable = 0
        for applied in document.fileReports.flatMap(\.appliedOperators) {
            guard let spelled = applied.key else {
                continue
            }
            guard let key = MutantKey(spelled: spelled) else {
                unreadable += 1
                continue
            }
            reportedKeys.insert(key)
            if applied.killedOnlyBySuspectTests?.value == true {
                flaggedKeys.insert(key)
            }
        }
        let summary = document.killingTestSummary
        let suspects = (summary?.tests ?? []).filter { $0.suspect?.value == true }.map { test in
            let reason = reason(of: test)
            return SuspectTest(
                name: test.name,
                file: test.file,
                reason: reason,
                files: reason == .reach ? test.files : nil,
                filesWithKills: reason == .reach ? summary?.filesWithKills : nil
            )
        }
        return Self(
            flagged: flaggedKeys,
            reported: reportedKeys,
            suspectsChecked: summary?.suspectsChecked == true,
            suspectTests: suspects.sorted { ($0.name, $0.file ?? "") < ($1.name, $1.file ?? "") },
            unreadableKeys: unreadable,
            read: true
        )
    }

    /// Why `test`, a suspect one, is suspect: a failed control run first,
    /// then flakiness alone (it didn't fail again alone, and failed again
    /// fewer than four times for each time it didn't), else reach. When
    /// four times the count of times it didn't fail again alone is past
    /// what an Int holds, that is more than any count of failures alone,
    /// so the test is flaky.
    private static func reason(of test: Test) -> SuspectReason {
        let notReproduced = test.notReproducedAlone ?? 0
        if (test.failedControlRuns ?? 0) > 0 {
            return .controlRun
        }
        if notReproduced > 0 {
            let exempted = failuresAlonePerExemption.multipliedReportingOverflow(by: notReproduced)
            if exempted.overflow || (test.failedAgainAlone ?? 0) < exempted.partialValue {
                return .flaky
            }
        }
        return .reach
    }

    /// Whether `mutant` is a kill by a failed test, the only kind a report
    /// judges.
    private static func isJudgeable(_ mutant: RecordedMutant) -> Bool {
        mutant.verdict == .killed && mutant.outcome == "failed"
    }

    /// Whether `mutant` is a kill only suspect tests made: suspect-only
    /// when flagged; not when unflagged and suspects were checked;
    /// unjudged when they weren't, when no entry that reads has its key,
    /// and for anything but a kill by a failed test.
    func judgement(of mutant: RecordedMutant) -> SuspectJudgement {
        guard Self.isJudgeable(mutant) else {
            return .unjudged
        }
        if flagged.contains(mutant.key) {
            return .suspectOnly
        }
        return suspectsChecked && reported.contains(mutant.key) ? .notSuspectOnly : .unjudged
    }

    /// How many of `mutants`' kills by a failed test no entry that reads
    /// has the key of, so they aren't judged; 0 for a report that wasn't
    /// read, which judges nothing anyway.
    func unreported(among mutants: [RecordedMutant]) -> Int {
        guard read else {
            return 0
        }
        return mutants.count { Self.isJudgeable($0) && reported.contains($0.key) == false }
    }
}
