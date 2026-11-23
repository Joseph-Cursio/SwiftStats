//
//  MappingHarness.swift
//  SwiftStatsCoreTests
//
//  Packages measured as a scan measures them, for the mutation mapping's
//  tests (M6, design §3, §4): a copy of the Coverage fixture, its
//  configuration excluding `Excluded.swift` and marking `Generated.swift`
//  generated as `CoverageFixture`'s does, a copy of the Mutation fixture,
//  or a small package of the files given. Results come from the fixtures'
//  recorded runs or from hand-written lines (`ResultsLines`); nothing is
//  built or run.
//

import Foundation
@testable import SwiftStatsCore

/// A measured package and the mapper onto it.
struct MappingHarness {
    /// The Coverage fixture's configuration.
    static let coverageConfiguration = """
        excluded:
          - Sources/Probe/Excluded.swift
        generated:
          - Sources/Probe/Generated.swift

        """
    /// When the Coverage fixture's recorded run started.
    static let coverageStartedAt = "2026-11-21T16:40:12.995Z"
    /// The Mutation fixture's targets, as its `Package.swift` declares them.
    static let mutationTargets = [
        DescribedTarget(
            name: "Core",
            type: "library",
            moduleType: "SwiftTarget",
            path: "Sources/Core",
            sources: ["Bounds.swift", "Dormant.swift", "NormalizeA.swift", "Signs.swift"]
        ),
        DescribedTarget(
            name: "CoreTests",
            type: "test",
            moduleType: "SwiftTarget",
            path: "Tests/CoreTests",
            sources: ["BoundsTests.swift", "NormalizeTests.swift", "SignTests.swift"],
            targetDependencies: ["Core"]
        ),
        DescribedTarget(
            name: "Extras",
            type: "library",
            moduleType: "SwiftTarget",
            path: "Sources/Extras",
            sources: ["NormalizeB.swift", "Scale.swift", "Unused.swift"]
        ),
        DescribedTarget(
            name: "ExtrasTests",
            type: "test",
            moduleType: "SwiftTarget",
            path: "Tests/ExtrasTests",
            sources: ["ScaleTests.swift"],
            targetDependencies: ["Extras"]
        )
    ]

    /// The package.
    let package: TemporaryPackage
    /// Its measurements.
    let measured: ScanMeasurements
    /// Its targets, the configuration's exclusions applied.
    let targets: [TargetSummary]
    /// Its configuration.
    let configuration: SwiftStatsConfiguration

    /// A mapper onto the package.
    var mapper: MutationMapper {
        MutationMapper(
            measured: measured,
            targets: targets,
            excluded: configuration.excluded.map(GlobPattern.init)
        )
    }

    /// The package `package`, measured under its `.swiftstats.yml`.
    init(_ package: TemporaryPackage) throws {
        self.package = package
        let file = package.root.appendingPathComponent(SwiftStatsConfiguration.fileName)
        configuration = try SwiftStatsConfiguration.load(
            FileManager.default.fileExists(atPath: file.path) ? file : nil,
            root: package.root
        )
        let resolved = TargetResolver.resolve(try package.describer.describePackage(at: package.root))
        targets = PackageScanner.excluding(resolved, by: configuration).targets
        measured = PackageScanner.measure(targets, root: package.root, configuration: configuration)
    }

    /// A copy of the Coverage fixture, measured; removed again if it can't
    /// be.
    static func coverage() throws -> Self {
        try coverage(adding: "")
    }

    /// A copy of the Coverage fixture whose configuration adds `settings`,
    /// measured; removed again if it can't be.
    static func coverage(adding settings: String) throws -> Self {
        try copy(
            CoverageFixture.directory,
            parts: ["Sources", "Tests", "Nested"],
            targets: CoverageFixture.targets,
            configuration: coverageConfiguration + settings
        )
    }

    /// A copy of the Mutation fixture, measured; removed again if it can't
    /// be.
    static func mutation() throws -> Self {
        try copy(MutationFixture.directory, parts: ["Sources", "Tests"], targets: mutationTargets, configuration: "")
    }

    /// A package of `fixture`'s folders `parts`, described as `targets`,
    /// whose `.swiftstats.yml` is `configuration` (none when it is empty),
    /// measured; removed again if it can't be.
    private static func copy(
        _ fixture: URL,
        parts: [String],
        targets: [DescribedTarget],
        configuration: String
    ) throws -> Self {
        let files = configuration.isEmpty ? [:] : [SwiftStatsConfiguration.fileName: configuration]
        let copy = try TemporaryPackage(files, targets: targets)
        do {
            for part in parts {
                try FileManager.default.copyItem(
                    at: fixture.appendingPathComponent(part),
                    to: copy.root.appendingPathComponent(part)
                )
            }
            return try Self(copy)
        } catch {
            copy.remove()
            throw error
        }
    }

    /// The Coverage fixture's recorded full run: its results and what its
    /// report judged.
    static func coverageRun() throws -> (results: MutationResults, suspects: SuspectReport) {
        try fullRun(of: MutationFixture.coverageDirectory)
    }

    /// The recorded full run of `fixture`: its results and what its report
    /// judged.
    static func fullRun(of fixture: URL) throws -> (results: MutationResults, suspects: SuspectReport) {
        (
            try MutationFixture.results(of: "full", in: fixture),
            try SuspectReport.decode(MutationFixture.data("report.json", of: "full", in: fixture))
        )
    }

    /// `report` with `complete` and `files` replaced and its mutants
    /// `mutants`, its records and counts worked out again.
    static func rebuilt(
        _ report: MutationReport,
        complete: Bool,
        files: [MutationFile],
        mutants: [Mutant]
    ) -> MutationReport {
        MutationReport(
            collectedAt: report.collectedAt,
            complete: complete,
            listsNotCovered: report.listsNotCovered,
            mode: report.mode,
            base: report.base,
            files: files,
            runs: report.runs,
            suspectTests: report.suspectTests,
            mutants: mutants
        )
    }

    /// A mutant SwiftMutator killed at `key`, making `after`, whose file
    /// hashed to `fileSHA256` (nil when not recorded).
    static func mutant(_ key: MutantKey, after: String, fileSHA256: String?) -> RecordedMutant {
        RecordedMutant(
            key: key,
            verdict: .killed,
            outcome: "failed",
            activated: .ran,
            endedBy: "exited",
            exitStatus: 1,
            killedBy: ["kills()"],
            failedTestCount: 1,
            killedByComplete: .complete,
            fileSHA256: fileSHA256,
            before: "1",
            after: after,
            description: "replaced the return value with \(after)",
            session: 1,
            durationSeconds: ResultsLines.durationSeconds,
            rerunBecause: nil,
            reused: false
        )
    }

    /// The report of `results`, judging nothing, as a full run of a clean
    /// tree at commit `c1`.
    func report(_ results: MutationResults) -> MutationReport {
        report(results, suspects: .unjudged)
    }

    /// The report of `results`, which `suspects` judged, as a full run of a
    /// clean tree at commit `c1`.
    func report(_ results: MutationResults, suspects: SuspectReport) -> MutationReport {
        report(results, suspects: suspects, resultsFile: ".swiftstats/mutation/runs/0/results.jsonl")
    }

    /// The report of `results`, which `suspects` judged, as a full run
    /// kept at `resultsFile` of a clean tree at commit `c1`.
    func report(_ results: MutationResults, suspects: SuspectReport, resultsFile: String) -> MutationReport {
        let run = MutationMapper.run(
            results,
            ordinal: 0,
            resultsFile: resultsFile,
            git: SnapshotHarness.git(commit: "c1"),
            suspects: suspects
        )
        return mapper.report(of: results, run: run, suspects: suspects)
    }

    /// A roll-up builder of `report` over the package.
    func rollupBuilder(_ report: MutationReport) -> MutationRollupBuilder {
        MutationRollupBuilder(targets: targets, records: measured.records, files: measured.files, report: report)
    }

    /// Where `mutant` goes.
    func place(_ mutant: RecordedMutant) -> MutationMapper.Placed {
        var anchorings: [String: MutantAnchoring] = [:]
        return mapper.place(mutant, anchorings: &anchorings)
    }

    /// The SHA-256 of the package's file at `path`.
    func hash(_ path: String) throws -> String {
        ContentHash.sha256(try Data(contentsOf: package.root.appendingPathComponent(path)))
    }

    /// Where a killed mutant at `path`, `line` and `column` of `operatorID`
    /// making `after` goes, its file hash the package's file's.
    func place(
        _ path: String,
        line: Int,
        column: Int,
        operatorID: String,
        after: String
    ) throws -> MutationMapper.Placed {
        let key = MutantKey(path: path, operatorID: operatorID, line: line, column: column, occurrence: 0)
        return place(Self.mutant(key, after: after, fileSHA256: try hash(path)))
    }

    /// Removes the package.
    func remove() {
        package.remove()
    }
}
