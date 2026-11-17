//
//  PackageScanner.swift
//  SwiftStatsCore
//
//  The T0 scan (PRD M0): ask SwiftPM for the package's targets and their
//  source files, parse every Swift file once, and derive both the function
//  records and the Sitrep-compatible counts from the same trees.
//

import Foundation
import SwiftParser
import SwiftSyntax

/// Scans a SwiftPM package at the syntax level.
public struct PackageScanner {
    /// Where package descriptions come from.
    private let describer: any PackageDescriber

    /// Creates a scanner that learns a package's targets through `describer`.
    public init(describer: any PackageDescriber) {
        self.describer = describer
    }

    /// Creates a scanner that asks SwiftPM for package descriptions.
    public init() {
        self.init(describer: SwiftPMPackageDescriber())
    }

    /// Records by file, then start position, then key.
    private static func recordOrder(_ lhs: FunctionRecord, _ rhs: FunctionRecord) -> Bool {
        if lhs.file != rhs.file {
            return lhs.file < rhs.file
        }
        if lhs.range.start != rhs.range.start {
            return lhs.range.start < rhs.range.start
        }
        return lhs.key < rhs.key
    }

    /// Warnings by file, then message.
    private static func warningOrder(_ lhs: ScanWarning, _ rhs: ScanWarning) -> Bool {
        if lhs.file != rhs.file {
            return (lhs.file ?? "") < (rhs.file ?? "")
        }
        return lhs.message < rhs.message
    }

    /// Scans the package rooted at `packageRoot`.
    public func scan(packageAt packageRoot: URL) throws -> ScanReport {
        let root = packageRoot.standardizedFileURL
        guard FileManager.default.fileExists(atPath: root.appendingPathComponent("Package.swift").path) else {
            throw ScanError.notAPackage(root.path)
        }
        let package = try describer.describePackage(at: root)
        let targets = TargetResolver.resolve(package)

        var warnings: [ScanWarning] = []
        var parsedByTarget: [[ParsedFile]] = []
        for target in targets {
            var parsed: [ParsedFile] = []
            for file in target.files {
                let url = root.appendingPathComponent(file)
                guard let source = try? String(contentsOf: url, encoding: .utf8) else {
                    warnings.append(ScanWarning(file: file, message: "not readable as UTF-8; skipped"))
                    continue
                }
                parsed.append(ParsedFile(path: file, source: source, tree: Parser.parse(source: source)))
            }
            parsedByTarget.append(parsed)
        }

        var records: [FunctionRecord] = []
        for (target, parsed) in zip(targets, parsedByTarget) {
            let testCaseClasses = target.isTest ? TestCaseClassIndex.testCaseClasses(in: parsed.map(\.tree)) : []
            for file in parsed {
                let context = FileContext(
                    module: target.name,
                    file: file.path,
                    isTestTarget: target.isTest,
                    testCaseClasses: testCaseClasses,
                    converter: SourceLocationConverter(fileName: file.path, tree: file.tree)
                )
                records += FunctionCollector.collect(file.tree, context: context)
            }
        }
        let (uniqueRecords, collisionWarnings) = KeyCollisions.resolve(records)

        let sitrepFiles = parsedByTarget.flatMap(\.self)
            .sorted { $0.path < $1.path }
            .map { SitrepFileVisitor.facts(for: $0.tree, source: $0.source, path: $0.path) }

        return ScanReport(
            schemaVersion: ScanReport.currentSchemaVersion,
            tool: .current,
            package: package.name,
            targets: targets,
            records: uniqueRecords.sorted(by: Self.recordOrder),
            sitrep: SitrepCounter.report(for: sitrepFiles),
            warnings: (warnings + collisionWarnings).sorted(by: Self.warningOrder)
        )
    }
}
