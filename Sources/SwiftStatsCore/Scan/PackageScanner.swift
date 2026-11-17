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
    /// The UTF-8 byte order mark.
    private static let byteOrderMark = Array("\u{FEFF}".utf8)

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

    /// Reads and parses each target's files, warning about unreadable ones.
    private static func parseFiles(of targets: [TargetSummary], root: URL) -> ([[ParsedFile]], [ScanWarning]) {
        var warnings: [ScanWarning] = []
        let parsedByTarget = targets.map { target in
            target.files.compactMap { file -> ParsedFile? in
                // Decoding drops a UTF-8 byte order mark, as Sitrep's reading
                // does; the compiler still counts its 3 bytes on line 1.
                guard let data = try? Data(contentsOf: root.appendingPathComponent(file)),
                      let source = String(data: data, encoding: .utf8) else {
                    warnings.append(ScanWarning(file: file, message: "not readable as UTF-8; skipped"))
                    return nil
                }
                return ParsedFile(
                    path: file,
                    source: source,
                    tree: Parser.parse(source: source),
                    hasByteOrderMark: data.starts(with: byteOrderMark)
                )
            }
        }
        return (parsedByTarget, warnings)
    }

    /// The function records of every parsed file, target by target.
    private static func collectRecords(
        _ targets: [TargetSummary],
        _ parsedByTarget: [[ParsedFile]]
    ) -> [FunctionRecord] {
        var records: [FunctionRecord] = []
        for (target, parsed) in zip(targets, parsedByTarget) {
            let testCaseClasses = target.isTest ? TestCaseClassIndex.testCaseClasses(in: parsed.map(\.tree)) : []
            for file in parsed {
                let context = FileContext(
                    module: target.name,
                    file: file.path,
                    isTestTarget: target.isTest,
                    testCaseClasses: testCaseClasses,
                    converter: SourceLocationConverter(fileName: file.path, tree: file.tree),
                    firstLineColumnOffset: file.hasByteOrderMark ? byteOrderMark.count : 0
                )
                records += FunctionCollector.collect(file.tree, context: context)
            }
        }
        return records
    }

    /// Scans the package rooted at `packageRoot`.
    public func scan(packageAt packageRoot: URL) throws -> ScanReport {
        let root = packageRoot.standardizedFileURL
        guard FileManager.default.fileExists(atPath: root.appendingPathComponent("Package.swift").path) else {
            throw ScanError.notAPackage(root.path)
        }
        let package = try describer.describePackage(at: root)
        let targets = TargetResolver.resolve(package)
        let (parsedByTarget, readWarnings) = Self.parseFiles(of: targets, root: root)
        let (records, collisionWarnings) = KeyCollisions.resolve(Self.collectRecords(targets, parsedByTarget))

        let sitrepFiles = parsedByTarget.flatMap(\.self)
            .sorted { $0.path < $1.path }
            .map { SitrepFileVisitor.facts(for: $0.tree, source: $0.source, path: $0.path) }

        return ScanReport(
            schemaVersion: ScanReport.currentSchemaVersion,
            tool: .current,
            package: package.name,
            targets: targets,
            records: records.sorted(by: Self.recordOrder),
            sitrep: SitrepCounter.report(for: sitrepFiles),
            warnings: (readWarnings + collisionWarnings).sorted(by: Self.warningOrder)
        )
    }
}
