//
//  MutationSignalHarness.swift
//  SwiftStatsCoreTests
//
//  Snapshots for M6's per-function signals (design §7.1, §7.2): a package
//  of four-line functions in a library `Lib`, and optionally a second
//  library `Other`, each with a test target of a chosen size depending on
//  it, given hand-made coverage (each function's line tally) and hand-made
//  mutation results (each function's mutants by verdict), stored and read
//  back, so the signals read what `report` reads. A function's mutants lie
//  on its second line, one column apart.
//

import Foundation
@testable import SwiftStatsCore
import Testing

/// Stores snapshots with chosen coverage and mutation results.
enum MutationSignalHarness {
    /// A mutant to plant in a function.
    struct Planted {
        /// Its verdict.
        let verdict: MutationVerdict
        /// For a kill, whether a test process crashed.
        var crash = false
        /// For a kill by a failing test, whether only suspect tests made
        /// it; nil when not judged.
        var suspectOnly: JSONFlag?
        /// The tests its kill names.
        var killedBy: [String] = []
        /// The operator that made it.
        var operatorID = "RelationalOperatorReplacement"
    }

    /// Where the mapping put a planted mutant.
    struct Placement {
        /// What it went to.
        let place: MutationPlace
        /// The record key, type or file it went to; nil when unmapped or
        /// dropped.
        let owner: String?
        /// Its anchor; nil when unmapped or dropped.
        let anchor: SourcePosition?
    }

    /// A function of the package: its line coverage and its mutants.
    struct Function {
        /// Its lines; nil for no coverage data.
        let lines: CoverageTally?
        /// Its mutants.
        let mutants: [Planted]
    }

    /// One library of the package.
    private struct Module {
        /// Its name.
        let name: String
        /// The file holding its functions.
        let file: String
        /// Its functions.
        let functions: [Function]
        /// The letter its functions' names start with.
        let letter: String

        /// The key of its function `index`.
        func key(_ index: Int) -> String {
            "\(name)::func \(letter)\(index)(_: Int) -> Int"
        }
    }

    /// How a package is laid out and what its results say, beyond `Lib`'s
    /// functions.
    struct Setup {
        /// `Other`'s functions; no `Other` when empty.
        var other: [Function] = []
        /// The checks of each module's test, by module; no test target for a
        /// module absent.
        var testLines: [String: Int] = ["Lib": MutationSignalHarness.defaultTestLines]
        /// Whether the results list code no test ran.
        var listsNotCovered = true
        /// Each file's disposition, by path; tested when absent.
        var dispositions: [String: MutationFileDisposition] = [:]
        /// The run's suspect tests.
        var suspects: [MutationSuspectTest] = []
        /// Whether the snapshot holds the coverage, rather than being a scan
        /// without `--coverage`.
        var withCoverage = true
        /// The store to keep the snapshot in; a new one, removed again, when nil.
        var store: SnapshotStore?
    }

    /// The file holding `Lib`'s functions.
    static let libFile = "Sources/Lib/Lib.swift"
    /// The file holding `Other`'s functions.
    static let otherFile = "Sources/Other/Other.swift"
    /// The lines one function and the blank line after it take.
    private static let pitch = 5
    /// The column of a function's first mutant.
    private static let firstColumn = 5
    /// The lines of a function.
    static let functionLines = 4
    /// The checks `Lib`'s test holds unless a setup says otherwise.
    static let defaultTestLines = 8
    /// The line of a function, from its first, its mutants lie on.
    private static let mutantLine = 1
    /// A funnel clause's sides: the whole and its parts.
    private static let clauseSides = 2

    /// The key of `Lib`'s function `index`.
    static func key(_ index: Int) -> String {
        "Lib::func f\(index)(_: Int) -> Int"
    }

    /// The key of `Other`'s function `index`.
    static func otherKey(_ index: Int) -> String {
        "Other::func g\(index)(_: Int) -> Int"
    }

    /// `count` mutants with `verdict`.
    static func planted(_ count: Int, _ verdict: MutationVerdict) -> [Planted] {
        Array(repeating: Planted(verdict: verdict), count: count)
    }

    /// `covered` of `total` lines.
    static func lines(_ covered: Int, of total: Int) -> CoverageTally {
        CoverageTally(covered: covered, total: total)
    }

    /// A function whose lines are all covered, holding `mutants`.
    static func covered(_ mutants: [Planted]) -> Function {
        Function(lines: lines(functionLines, of: functionLines), mutants: mutants)
    }

    /// `lib` as `Lib`'s functions, laid out as the default setup says.
    static func stored(_ lib: [Function]) throws -> StoredSnapshot {
        try stored(lib, Setup())
    }

    /// `lib` as `Lib`'s functions and `setup.other` as `Other`'s, each
    /// module's test target holding a test of `setup.testLines` checks,
    /// with the coverage (when `setup.withCoverage`) and mutants they give,
    /// the results listing code no test ran and each file's disposition as
    /// `setup` says, and its suspect tests as the run's; stored in
    /// `setup.store` (a new one when nil) and read back.
    static func stored(_ lib: [Function], _ setup: Setup) throws -> StoredSnapshot {
        let other = setup.other
        let modules = [
            Module(name: "Lib", file: libFile, functions: lib, letter: "f"),
            Module(name: "Other", file: otherFile, functions: other, letter: "g")
        ]
        .filter { $0.functions.isEmpty == false }
        let (files, targets) = layout(modules, testLines: setup.testLines)
        var records: [CoverageRecord] = []
        var mutants: [Mutant] = []
        for module in modules {
            for (index, function) in module.functions.enumerated() {
                let owner = module.key(index)
                records.append(record(owner, lines: function.lines))
                mutants += function.mutants.enumerated().map { offset, planted in
                    let line = index * pitch + mutantLine + 1
                    return mutant(planted, path: module.file, line: line, column: firstColumn + offset, owner: owner)
                }
            }
        }
        let report = MutationReport(
            collectedAt: "2026-11-21T09:00:00.000Z",
            complete: true,
            listsNotCovered: setup.listsNotCovered,
            mode: .full,
            base: nil,
            files: modules.map { module in
                MutationFile(
                    path: module.file,
                    sha256: "abc",
                    disposition: setup.dispositions[module.file] ?? .tested,
                    changedTest: false,
                    run: 0
                )
            },
            runs: [run(listsNotCovered: setup.listsNotCovered)],
            suspectTests: setup.suspects,
            mutants: mutants
        )
        return try stored(
            files,
            targets: targets,
            coverage: setup.withCoverage ? coverage(records) : nil,
            mutation: report,
            store: setup.store
        )
    }

    /// The files and targets of a package of `modules`, each with a test
    /// target depending on it whose one test has `testLines` checks by
    /// module (none when absent).
    private static func layout(
        _ modules: [Module],
        testLines: [String: Int]
    ) -> (files: [String: String], targets: [DescribedTarget]) {
        var files: [String: String] = [:]
        var targets: [DescribedTarget] = []
        for module in modules {
            files[module.file] = source(module.functions.count, letter: module.letter)
            targets.append(DescribedTarget(
                name: module.name,
                type: "library",
                moduleType: "SwiftTarget",
                path: "Sources/\(module.name)",
                sources: [URL(fileURLWithPath: module.file).lastPathComponent]
            ))
            guard let count = testLines[module.name] else {
                continue
            }
            files["Tests/\(module.name)Tests/\(module.name)Tests.swift"] = test(module.name, lines: count)
            targets.append(DescribedTarget(
                name: "\(module.name)Tests",
                type: "test",
                moduleType: "SwiftTarget",
                path: "Tests/\(module.name)Tests",
                sources: ["\(module.name)Tests.swift"],
                targetDependencies: [module.name]
            ))
        }
        return (files, targets)
    }

    /// The signal `name` of `snapshot` with the default thresholds.
    static func signal(_ name: SignalName, of snapshot: StoredSnapshot) throws -> SignalResult {
        try signal(name, of: snapshot, thresholds: SignalThresholds())
    }

    /// The signal `name` of `snapshot` with `thresholds`.
    static func signal(
        _ name: SignalName,
        of snapshot: StoredSnapshot,
        thresholds: SignalThresholds
    ) throws -> SignalResult {
        let signals = SignalEngine.signals(of: SignalInputs(snapshot: snapshot), thresholds: thresholds)
        return try #require(signals.first { $0.name == name })
    }

    /// The clauses of `rule`'s funnel whose parts don't sum to their
    /// whole: each `<whole> … = <part> … + <part> …` clause between
    /// semicolons, the first number of each side and each part compared.
    static func unbalanced(_ rule: String) -> [String] {
        rule.components(separatedBy: "; ").filter { clause in
            let sides = clause.components(separatedBy: " = ")
            guard sides.count == clauseSides, let whole = firstNumber(sides[0]) else {
                return false
            }
            let parts = sides[1].components(separatedBy: " + ").compactMap(firstNumber)
            return parts.reduce(0, +) != whole
        }
    }

    /// The first whole number in `text`; nil when it holds none.
    private static func firstNumber(_ text: String) -> Int? {
        let digits = text.drop { $0.isNumber == false }.prefix(while: \.isNumber)
        return Int(digits)
    }

    /// `count` four-line functions named `<letter>0`, `<letter>1`, …, each
    /// followed by a blank line.
    private static func source(_ count: Int, letter: String) -> String {
        (0..<count).map { index in
            "func \(letter)\(index)(_ value: Int) -> Int {\n    let step = value + \(index)\n    return step * 2\n}\n"
        }
        .joined(separator: "\n")
    }

    /// A test file for `module` whose one test has `lines` checks.
    private static func test(_ module: String, lines: Int) -> String {
        let checks = String(repeating: "    #expect(true)\n", count: lines)
        return "import Testing\n\n@Test func \(module.lowercased())Checks() {\n\(checks)}\n"
    }

    /// `files` as a package of `targets`, scanned, given `coverage` (none
    /// when nil) and `mutation` as run results, stored in `store` (a new
    /// one when nil) and read back.
    private static func stored(
        _ files: [String: String],
        targets: [DescribedTarget],
        coverage: CoverageReport?,
        mutation: MutationReport,
        store: SnapshotStore?
    ) throws -> StoredSnapshot {
        let package = try TemporaryPackage(files, targets: targets)
        defer { package.remove() }
        var snapshot = try SnapshotHarness.scan(package, commit: "c1")
        let git = snapshot.info.git
        if let coverage {
            snapshot = CoverageSnapshots.replacing(
                snapshot,
                git: git,
                coverage: coverage,
                run: CoverageSnapshots.ran(options: [])
            )
        }
        snapshot = MutationSnapshots.replacing(
            snapshot,
            git: git,
            mutation: mutation,
            run: MutationSnapshots.ran(identity: MutationSnapshots.identity)
        )
        if let store {
            return try store.load(id: try store.save(snapshot))
        }
        let directory = try SnapshotHarness.temporaryDirectory("MutationSignals")
        defer { try? FileManager.default.removeItem(at: directory) }
        let fresh = try SnapshotStore(at: directory.appendingPathComponent("stats.sqlite"))
        return try fresh.load(id: try fresh.save(snapshot))
    }
}
