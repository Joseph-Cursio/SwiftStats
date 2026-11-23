//
//  MutationMapper+Report.swift
//  SwiftStatsCore
//
//  A full run's results as a mutation report (M6, design §3): every
//  mutant placed, the run's suspect tests, and its tree, every Swift path
//  of its last header with each production path `tested` by the run and
//  every other one `untested`. A `--since` merge (`MutationMerge`) builds
//  its report from the same pieces: the run's mutants placed, its suspect
//  tests, and which paths are production or test files.
//

extension MutationMapper {
    /// The tests `suspects` judged suspect, as run `ordinal`'s.
    static func suspectTests(_ suspects: SuspectReport, run ordinal: Int) -> [MutationSuspectTest] {
        suspects.suspectTests.map { test in
            MutationSuspectTest(
                name: test.name,
                file: test.file,
                run: ordinal,
                why: test.reason,
                files: test.files,
                filesWithKills: test.filesWithKills
            )
        }
    }

    /// The report of `results`, left by `run` (a full run), whose kills
    /// `suspects` judged: every mutant placed, the run's tree, its suspect
    /// tests, and the counts.
    func report(of results: MutationResults, run: MutationRunRecord, suspects: SuspectReport) -> MutationReport {
        MutationReport(
            collectedAt: run.startedAt,
            complete: results.complete,
            listsNotCovered: results.listsNotCovered,
            mode: run.mode,
            base: nil,
            files: files(of: results.tree, run: run.ordinal),
            runs: [run],
            suspectTests: Self.suspectTests(suspects, run: run.ordinal),
            mutants: mutants(of: results, run: run.ordinal, suspects: suspects)
        )
    }

    /// The report of a full run that found no code SwiftMutator could test
    /// (its exit 255 with the nothing-to-test line, design §1.5), started
    /// at `collectedAt`, over `tree`, the scan's files with their hashes:
    /// complete, with no run and no mutant, listing no code no test ran,
    /// each production path unlisted (it holds no mutant SwiftMutator
    /// tests) and every other one untested.
    func nothingTested(in tree: [String: String], collectedAt: String) -> MutationReport {
        MutationReport(
            collectedAt: collectedAt,
            complete: true,
            listsNotCovered: false,
            mode: .full,
            base: nil,
            files: tree.keys.filter { $0.hasSuffix(Self.swiftExtension) }.sorted().map { path in
                MutationFile(
                    path: path,
                    sha256: tree[path],
                    disposition: isProduction(path) ? .unlisted : .untested,
                    changedTest: false,
                    run: nil
                )
            },
            runs: [],
            suspectTests: [],
            mutants: []
        )
    }

    /// Every mutant of `results`, tested by run `ordinal`, whose kills
    /// `suspects` judged, placed.
    func mutants(of results: MutationResults, run ordinal: Int, suspects: SuspectReport) -> [Mutant] {
        var anchorings: [String: MutantAnchoring] = [:]
        return results.mutants.map { recorded in
            Self.mutant(recorded, placed: place(recorded, anchorings: &anchorings), run: ordinal, suspects: suspects)
        }
    }

    /// The Swift paths of `tree`, a run's last tree, each production path
    /// tested by run `ordinal` and every other one untested.
    func files(of tree: [String: String], run ordinal: Int) -> [MutationFile] {
        tree.keys.filter { $0.hasSuffix(Self.swiftExtension) }.sorted().map { path in
            let isProduction = isProduction(path)
            return MutationFile(
                path: path,
                sha256: tree[path],
                disposition: isProduction ? .tested : .untested,
                changedTest: false,
                run: isProduction ? ordinal : nil
            )
        }
    }

    /// Whether the file at `path`, relative to the project, is a
    /// production file: one SwiftMutator's mutants in it are kept or
    /// unmapped, never dropped by design.
    func isProduction(_ path: String) -> Bool {
        switch classify(path) {
        case .kept, .unmapped:
            true

        case .build, .outsideRoot, .testFile, .otherLanguage, .otherPackage:
            false
        }
    }

    /// Whether the file at `path`, relative to the project, is in a test
    /// target's directory.
    func isTestFile(_ path: String) -> Bool {
        if case .testFile = classify(path) {
            return true
        }
        return false
    }
}
