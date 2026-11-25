import Foundation
@testable import SwiftStatsCore
import Testing

/// Writes what SwiftStats reads from a real T1 build's output, for the
/// independent checker to compare (M7, design §11, §13 step 2b): the
/// reader's parse in the shape `Scripts/index-check.py build-lines --json`
/// writes, which its `--compare` reads, and, given the package, its build
/// block and `swiftc` findings, which a scan JSON carries for `build`.
/// Skipped unless `SWIFTSTATS_BUILD_EXPORT` names a JSON file saying what
/// to read and where to write, so a plain `swift test` reads nothing real.
@Suite(
    "Build output export",
    .enabled(if: ProcessInfo.processInfo.environment[BuildFixture.exportVariable] != nil)
)
struct BuildOutputExportTests {
    /// What to read and where to write.
    private struct Request: Decodable {
        /// The build's standard error (or a file holding both streams).
        let stderr: String
        /// The build's task log; none for a combined file.
        let log: String?
        /// Where the parse goes.
        let lines: String
        /// The package's root, to map onto; none to write only the parse.
        let package: String?
        /// `swift package describe --type json` of the package.
        let describe: String?
        /// How the output spells the package root (`@ROOT@` in a
        /// recording); its real path when absent.
        let rootSpelling: String?
        /// How the output spells the build directory; the root's
        /// `.swiftstats/index-build` when absent.
        let buildSpelling: String?
        /// Where the build block and findings go.
        let mapped: String?
    }

    /// One diagnostic as the checker's parse writes it.
    private static func checkerForm(_ diagnostic: BuildDiagnostic) -> [String: Any] {
        var form: [String: Any] = [
            "severity": diagnostic.severity.rawValue,
            "message": diagnostic.message,
            "id": diagnostic.identifier ?? NSNull(),
            "group": diagnostic.group ?? NSNull(),
            "file": NSNull(),
            "macro": NSNull(),
            "column": NSNull(),
            "origin": diagnostic.origin.map { ["file": $0.path, "line": $0.line, "column": $0.column] } ?? NSNull()
        ]
        switch diagnostic.location {
        case .file(let place):
            form["place"] = "file"
            form["file"] = place.path
            form["line"] = place.line
            form["column"] = place.column

        case let .macro(name, line, column):
            form["place"] = "macro"
            form["macro"] = name
            form["line"] = line
            form["column"] = column

        case .unknown(let line):
            form["place"] = "unknown"
            form["line"] = line
        }
        return form
    }

    /// The reader's parse in the checker's shape.
    private static func parse(_ output: BuildOutput) -> [String: Any] {
        [
            "counters": [
                "escapedLines": output.escapedLines,
                "unparsedTimingLines": output.unparsedTimingLines,
                "otherWarningLines": output.otherWarningLines,
                "functionEntries": output.entries.count { $0.kind == .function },
                "expressionEntries": output.entries.count { $0.kind == .expression }
            ],
            "entries": output.entries.map { entry -> [String: Any] in
                [
                    "kind": entry.kind.rawValue,
                    "hundredths": entry.hundredths,
                    "file": entry.place?.path ?? NSNull(),
                    "line": entry.place?.line ?? NSNull(),
                    "column": entry.place?.column ?? NSNull()
                ]
            },
            "diagnostics": output.diagnostics.map(checkerForm)
        ]
    }

    @Test("the reader's parse and mapping are written where the request says")
    func export() throws {
        let requestPath = try #require(ProcessInfo.processInfo.environment[BuildFixture.exportVariable])
        let request = try JSONDecoder().decode(Request.self, from: Data(contentsOf: URL(fileURLWithPath: requestPath)))
        let stderr = try Data(contentsOf: URL(fileURLWithPath: request.stderr))
        let log = try request.log.map { try Data(contentsOf: URL(fileURLWithPath: $0)) } ?? Data()
        let output = BuildOutputReader.read(stderr: stderr, log: log)
        let lines = try JSONSerialization.data(withJSONObject: Self.parse(output), options: [.sortedKeys])
        try lines.write(to: URL(fileURLWithPath: request.lines))
        guard let package = request.package, let describe = request.describe, let mapped = request.mapped else {
            return
        }
        let root = URL(fileURLWithPath: package)
        let described = try JSONDecoder().decode(
            DescribedPackage.self,
            from: Data(contentsOf: URL(fileURLWithPath: describe))
        )
        let targets = TargetResolver.resolve(described)
        let measured = PackageScanner.measure(targets, root: root, configuration: SwiftStatsConfiguration())
        let rootSpelling = request.rootSpelling ?? BuildFixture.realPath(root)
        let buildSpelling = request.buildSpelling ?? rootSpelling + "/.swiftstats/index-build"
        let timings = TimingMapper(measured: measured, root: rootSpelling, build: buildSpelling, changedFiles: [])
            .map(output.entries)
        let warnings = WarningReader(
            measured: measured,
            targets: targets,
            root: rootSpelling,
            build: buildSpelling,
            changedFiles: []
        ).read(output.diagnostics)
        let report = BuildReport(output: output, timings: timings, warnings: warnings, changedFiles: 0, complete: true)
        let findings = warnings.findings.map(FindingMapper(measured: measured).finding(for:))
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes]
        let block = try JSONSerialization.jsonObject(with: encoder.encode(report))
        let found = try JSONSerialization.jsonObject(with: encoder.encode(findings))
        let written = try JSONSerialization.data(
            withJSONObject: ["build": block, "findings": found],
            options: [.sortedKeys, .prettyPrinted]
        )
        try written.write(to: URL(fileURLWithPath: mapped))
    }
}
