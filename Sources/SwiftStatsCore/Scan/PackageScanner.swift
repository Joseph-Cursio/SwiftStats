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
    let describer: any PackageDescriber
    /// Where the external collectors' tools come from.
    let tools: ToolLocator

    /// Creates a scanner that learns a package's targets through
    /// `describer` and finds external tools with `tools`.
    public init(describer: any PackageDescriber, tools: ToolLocator = .path) {
        self.describer = describer
        self.tools = tools
    }

    /// Creates a scanner that asks SwiftPM for package descriptions and
    /// finds external tools with `tools`.
    public init(tools: ToolLocator = .path) {
        self.init(describer: SwiftPMPackageDescriber(), tools: tools)
    }

    /// Records by file, then start position, then key.
    static func recordOrder(_ lhs: FunctionRecord, _ rhs: FunctionRecord) -> Bool {
        if lhs.file != rhs.file {
            return lhs.file < rhs.file
        }
        if lhs.range.start != rhs.range.start {
            return lhs.range.start < rhs.range.start
        }
        return lhs.key < rhs.key
    }

    /// Types by file, then start position, then name.
    static func typeOrder(_ lhs: TypeRecord, _ rhs: TypeRecord) -> Bool {
        if lhs.file != rhs.file {
            return lhs.file < rhs.file
        }
        if lhs.range.start != rhs.range.start {
            return lhs.range.start < rhs.range.start
        }
        return lhs.name < rhs.name
    }

    /// Findings by their first location, then tool, rule and message.
    static func findingOrder(_ lhs: Finding, _ rhs: Finding) -> Bool {
        let left = lhs.locations.first
        let right = rhs.locations.first
        let leftPlace = (left?.file ?? "", left?.line ?? 0, left?.column ?? 0)
        let rightPlace = (right?.file ?? "", right?.line ?? 0, right?.column ?? 0)
        if leftPlace != rightPlace {
            return leftPlace < rightPlace
        }
        return (lhs.tool, lhs.rule, lhs.message) < (rhs.tool, rhs.rule, rhs.message)
    }

    /// Warnings by file, then message.
    static func warningOrder(_ lhs: ScanWarning, _ rhs: ScanWarning) -> Bool {
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

    /// The function, type and file records of every parsed file, target by
    /// target; files matching `generated` or carrying a known header are
    /// marked generated.
    private static func collect(
        _ targets: [TargetSummary],
        _ parsedByTarget: [[ParsedFile]],
        generated: [GlobPattern]
    ) -> CollectedRecords {
        var collected = CollectedRecords()
        // A test target's XCTestCase subclasses may descend from a base class
        // in another of the package's targets (swift-collections'
        // `CollectionTestCase`), so the whole package is indexed too.
        let packageTestCases = TestCaseClassIndex.testCaseClasses(in: parsedByTarget.flatMap { $0.map(\.tree) })
        for (target, parsed) in zip(targets, parsedByTarget) {
            let testCaseClasses = target.isTest
                ? TestCaseClassIndex.testCaseClasses(in: parsed.map(\.tree)).union(packageTestCases)
                : []
            for file in parsed {
                let context = FileContext(
                    module: target.name,
                    file: file.path,
                    isTestTarget: target.isTest,
                    testCaseClasses: testCaseClasses,
                    converter: SourceLocationConverter(fileName: file.path, tree: file.tree),
                    firstLineColumnOffset: file.hasByteOrderMark ? byteOrderMark.count : 0
                )
                collected.records += FunctionCollector.collect(file.tree, context: context)
                collected.types += TypeCollector.collect(file.tree, context: context)
                collected.declarations += DeclarationCollector.collect(file.tree, module: target.name)
                collected.markers += MarkerCollector.collect(file.tree, context: context)
                collected.topLevelLines[file.path] = FunctionCollector.topLevelLines(
                    in: file.tree,
                    converter: context.converter
                )
                collected.files.append(FileMeasure.record(
                    of: file,
                    module: target.name,
                    generated: GeneratedCode.isGenerated(file, globs: generated)
                ))
            }
        }
        return collected
    }

    /// The targets with the files `configuration` excludes left out, and
    /// those files, sorted.
    static func excluding(
        _ targets: [TargetSummary],
        by configuration: SwiftStatsConfiguration
    ) -> (targets: [TargetSummary], excluded: [String]) {
        let globs = configuration.excluded.map(GlobPattern.init)
        var excluded: [String] = []
        let kept = targets.map { target in
            let files = target.files.filter { file in
                let isExcluded = globs.contains { $0.matches(file) }
                if isExcluded {
                    excluded.append(file)
                }
                return isExcluded == false
            }
            return TargetSummary(
                name: target.name,
                type: target.type,
                isTest: target.isTest,
                path: target.path,
                files: files,
                dependencies: target.dependencies
            )
        }
        return (kept, excluded.sorted())
    }

    /// A warning for each key of `.swiftstats.yml` no collector reads yet.
    static func unusedKeyWarnings(_ configuration: SwiftStatsConfiguration) -> [ScanWarning] {
        configuration.unusedKeys.map { key in
            ScanWarning(
                file: configuration.source,
                message: "`\(key)` is accepted but not used yet; it has no effect on this scan"
            )
        }
    }

    /// The Sitrep facts of every file, in path order, and a warning for each
    /// type name declared with different first parents.
    private static func sitrep(_ parsedByTarget: [[ParsedFile]]) -> (SitrepReport, [ScanWarning]) {
        let sitrepFiles = parsedByTarget.flatMap(\.self)
            .sorted { $0.path < $1.path }
            .map { SitrepFileVisitor.facts(for: $0.tree, source: $0.source, path: $0.path) }
        let warnings = SitrepCounter.namesWithConflictingParents(in: sitrepFiles).map { name in
            ScanWarning(
                file: nil,
                message: "sitrep: \(name) is declared with different first parents; "
                    + "its UIKit and SwiftUI line counts follow the first declaration in path order"
            )
        }
        return (SitrepCounter.report(for: sitrepFiles), warnings)
    }

    /// SwiftStats' own measurements of `targets`' files.
    static func measure(
        _ targets: [TargetSummary],
        root: URL,
        configuration: SwiftStatsConfiguration
    ) -> ScanMeasurements {
        let (parsedByTarget, readWarnings) = parseFiles(of: targets, root: root)
        let collected = collect(targets, parsedByTarget, generated: configuration.generated.map(GlobPattern.init))
        let (resolved, collisionWarnings) = KeyCollisions.resolve(collected.records)
        let ignoresCases = SwiftLintSettings.ignoresCaseStatements(packageRoot: root)
        let parsed = zip(targets, parsedByTarget).flatMap { target, files in files.map { (target.name, $0) } }
        let (records, scoreWarnings) = ComplexityScorer.score(
            resolved,
            files: parsed,
            ignoresCaseStatements: ignoresCases
        )
        let (sitrep, sitrepWarnings) = sitrep(parsedByTarget)
        return ScanMeasurements(
            records: records,
            types: collected.types,
            files: collected.files,
            declarations: collected.declarations,
            markers: collected.markers,
            topLevelLines: collected.topLevelLines,
            tests: TestInventory.tests(
                records: records,
                parsed: parsed,
                testModules: Set(targets.filter(\.isTest).map(\.name)),
                generatedFiles: Set(collected.files.filter(\.generated).map(\.path))
            ),
            parsed: parsed,
            sitrep: sitrep,
            metrics: ComplexityScorer.metricsInfo(ignoresCaseStatements: ignoresCases),
            warnings: readWarnings + collisionWarnings + scoreWarnings + sitrepWarnings
        )
    }

    /// `raw` findings attached to the measured records, types and files.
    static func attach(_ raw: [RawFinding], to measured: ScanMeasurements) -> [Finding] {
        let mapper = FindingMapper(
            records: measured.records,
            types: measured.types,
            files: measured.files,
            topLevelLines: measured.topLevelLines
        )
        return raw.map(mapper.finding(for:))
    }

    /// Scans the package rooted at `packageRoot`, with the `.swiftstats.yml`
    /// in its root when there is one.
    public func scan(packageAt packageRoot: URL) throws -> ScanReport {
        let file = packageRoot.standardizedFileURL.appendingPathComponent(SwiftStatsConfiguration.fileName)
        return try scan(
            packageAt: packageRoot,
            configurationFile: FileManager.default.fileExists(atPath: file.path) ? file : nil
        )
    }

    /// Scans the package rooted at `packageRoot` with the configuration in
    /// `configurationFile`, or the default configuration when it is nil.
    public func scan(packageAt packageRoot: URL, configurationFile: URL?) throws -> ScanReport {
        try run(packageAt: packageRoot, configurationFile: configurationFile).report
    }
}
