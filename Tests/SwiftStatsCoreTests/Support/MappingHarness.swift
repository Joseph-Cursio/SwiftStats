//
//  MappingHarness.swift
//  SwiftStatsCoreTests
//
//  Packages measured as a scan measures them, for the mutation mapping's
//  tests (M6, design §3): a copy of the Coverage fixture, its
//  configuration excluding `Excluded.swift` and marking `Generated.swift`
//  generated as `CoverageFixture`'s does, or a small package of the files
//  given. Results come from the fixture's recorded run or from
//  hand-written lines (`ResultsLines`); nothing is built or run.
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
        let copy = try TemporaryPackage(
            [SwiftStatsConfiguration.fileName: coverageConfiguration + settings],
            targets: CoverageFixture.targets
        )
        do {
            for part in ["Sources", "Tests", "Nested"] {
                try FileManager.default.copyItem(
                    at: CoverageFixture.directory.appendingPathComponent(part),
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
        let fixture = MutationFixture.coverageDirectory
        return (
            try MutationFixture.results(of: "full", in: fixture),
            try SuspectReport.decode(MutationFixture.data("report.json", of: "full", in: fixture))
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
