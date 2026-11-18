//
//  SwiftLintParityTests.swift
//  SwiftStatsCoreTests
//
//  PRD M1a done-when (1): on swift-algorithms, for every `func` and `init`,
//  SwiftLint 0.65.1's `cyclomatic_complexity` (0 when it reports nothing)
//  equals the SwiftLint-compatible count on SwiftStats' record. This checks
//  the join of SwiftCodeMetrics' scores onto SwiftStats' records.
//

import Foundation
import SwiftParser
import SwiftStatsCore
import Testing

@Suite("SwiftLint parity", .enabled(if: SwiftLintRunner.isAvailable, "needs swiftlint 0.65.1"))
struct SwiftLintParityTests {
    /// swift-algorithms, where it is checked out on this machine.
    private static let corpus = FileManager.default.homeDirectoryForCurrentUser
        .appendingPathComponent("GitHub_projects/swift-algorithms")

    @Test("every func and init matches SwiftLint on swift-algorithms")
    func swiftAlgorithms() throws {
        try #require(FileManager.default.fileExists(atPath: Self.corpus.path), "corpus missing: \(Self.corpus.path)")
        let report = try PackageScanner(tools: .nowhere).scan(packageAt: Self.corpus)
        let root = Self.corpus.standardizedFileURL.path
        let scannedFiles = report.targets.flatMap(\.files).sorted()
        let paths = scannedFiles.map { root + "/" + $0 }
        let reported = try SwiftLintRunner.complexities(
            of: paths,
            ignoresCaseStatements: report.metrics.swiftLintIgnoresCaseStatements
        )
        var checked = 0
        var nonZero = 0
        var mismatches: [String] = []
        for file in scannedFiles {
            let path = root + "/" + file
            let source = try String(contentsOfFile: path, encoding: .utf8)
            let tokens = SwiftLintReportTokens.positions(in: Parser.parse(source: source), file: path)
            let scored = report.records.filter { record in
                record.file == file && (record.kind == .function || record.kind == .initializer)
            }
            for record in scored {
                let start = "\(record.range.start.line):\(record.range.start.column)"
                guard let complexity = record.complexity else {
                    mismatches.append("\(file):\(start) \(record.key): no score joined")
                    continue
                }
                guard let token = tokens[start] else {
                    mismatches.append("\(file):\(start) \(record.key): no SwiftLint report position")
                    continue
                }
                let expected = reported["\(path):\(token)"] ?? 0
                checked += 1
                nonZero += expected > 0 ? 1 : 0
                if complexity.swiftLintCompatible != expected {
                    let actual = complexity.swiftLintCompatible
                    let location = "\(file):\(token) \(record.key)"
                    mismatches.append("\(location): SwiftStats \(actual), SwiftLint \(expected)")
                }
            }
        }

        #expect(report.warnings.isEmpty, "\(report.warnings.map(\.message))")
        #expect(checked > 100)
        // SwiftLint's paths matched ours: most functions it reports score above 0.
        #expect(nonZero > checked / 4, "only \(nonZero) of \(checked) matched a SwiftLint report")
        #expect(mismatches.isEmpty, "\(mismatches.prefix(40).joined(separator: "\n"))")
    }

    /// PRD M1b done-when (2): the SwiftLint adapter's counts per rule equal
    /// `swiftlint lint --reporter json` run on the targets' directories.
    @Test("violation counts per rule match swiftlint lint on swift-algorithms")
    func violationCounts() throws {
        try #require(FileManager.default.fileExists(atPath: Self.corpus.path), "corpus missing: \(Self.corpus.path)")
        let binary = try #require(SwiftLintRunner.binary)
        let report = try PackageScanner(tools: ToolLocator { $0 == "swiftlint" ? binary : nil })
            .scan(packageAt: Self.corpus)
        let violations = report.findings.filter { $0.tool == "swiftlint" }
        let counts = violations.reduce(into: [String: Int]()) { counts, finding in
            counts[finding.rule, default: 0] += 1
        }

        #expect(report.collectors.first { $0.name == "swiftlint" }?.state == .ran)
        #expect(counts.isEmpty == false)
        let paths = Set(report.targets.map(\.path)).sorted()
        #expect(counts == (try SwiftLintRunner.violationCounts(in: Self.corpus, paths: paths)))
        #expect(report.findings.allSatisfy { $0.locations.allSatisfy { $0.attachedTo != .unscanned } })
    }
}
