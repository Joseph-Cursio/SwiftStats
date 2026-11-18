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
                collected.records += FunctionCollector.collect(file.tree, context: context)
                collected.types += TypeCollector.collect(file.tree, context: context)
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
    private static func excluding(
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
                files: files
            )
        }
        return (kept, excluded.sorted())
    }

    /// A warning for each key of `.swiftstats.yml` no collector reads yet.
    private static func unusedKeyWarnings(_ configuration: SwiftStatsConfiguration) -> [ScanWarning] {
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
        let root = packageRoot.standardizedFileURL
        guard FileManager.default.fileExists(atPath: root.appendingPathComponent("Package.swift").path) else {
            throw ScanError.notAPackage(root.path)
        }
        let configuration = try SwiftStatsConfiguration.load(configurationFile, root: root)
        let package = try describer.describePackage(at: root)
        let (targets, excludedFiles) = Self.excluding(TargetResolver.resolve(package), by: configuration)
        let (parsedByTarget, readWarnings) = Self.parseFiles(of: targets, root: root)
        let collected = Self.collect(
            targets,
            parsedByTarget,
            generated: configuration.generated.map(GlobPattern.init)
        )
        let (resolved, collisionWarnings) = KeyCollisions.resolve(collected.records)
        let ignoresCases = SwiftLintSettings.ignoresCaseStatements(packageRoot: root)
        let modules = zip(targets, parsedByTarget).flatMap { target, files in files.map { (target.name, $0) } }
        let (records, scoreWarnings) = ComplexityScorer.score(
            resolved,
            files: modules,
            ignoresCaseStatements: ignoresCases
        )
        let (sitrep, sitrepWarnings) = Self.sitrep(parsedByTarget)
        let warnings = readWarnings + collisionWarnings + scoreWarnings + sitrepWarnings
            + Self.unusedKeyWarnings(configuration)
        return ScanReport(
            schemaVersion: ScanReport.currentSchemaVersion,
            tool: .current,
            metrics: ComplexityScorer.metricsInfo(ignoresCaseStatements: ignoresCases),
            package: package.name,
            configuration: ScanConfigurationSummary(
                excluded: configuration.excluded,
                excludedFiles: excludedFiles,
                generated: configuration.generated
            ),
            targets: targets,
            records: records.sorted(by: Self.recordOrder),
            types: collected.types.sorted(by: Self.typeOrder),
            files: collected.files.sorted { $0.path < $1.path },
            rollups: RollupBuilder.rollups(
                targets: targets,
                records: records,
                types: collected.types,
                files: collected.files
            ),
            sitrep: sitrep,
            warnings: warnings.sorted(by: Self.warningOrder)
        )
    }
}
