//
//  CoverageMapper.swift
//  SwiftStatsCore
//
//  Maps a coverage export onto the scan (M5, PRD §7.8). The export's files
//  are sorted by `CoverageFileClassifier`; in a kept file each entry's
//  code regions go where `PositionPlacement` puts it, its skipped ones
//  into the file's skipped ranges. An entry spanning several files or
//  holding an expansion region is unmapped. A testable executable's
//  top-level entry (`<module>_main`) goes to its file's top-level-code
//  record without the anchor rule: its regions starting on statement lines
//  to the record (none: the record has no entry), the rest (eager
//  globals) to the file; statement lines none of its regions spans are in
//  a top-level `#if` with no active clause, for which the compiler emits
//  nothing, and become skipped ranges of the file. Every production
//  record then gets its figures (`CoverageRecordLines`) and the test
//  targets that ran it, or a reason for having none, and a public function
//  its link rule and linked tests (`CoverageTestLinks`); attachments get
//  the lines no record spans; each kept file gets its line data.
//

import Foundation

/// Maps a coverage export onto the scan's records.
struct CoverageMapper {
    /// An entry mapped to a record.
    private struct MappedEntry {
        /// Its mangled name.
        let name: String
        /// The code regions it gives the record.
        let regions: [CoverageRegion]
        /// Its skipped regions.
        let skipped: [CoverageRegion]
    }

    /// What mapping the entries gathered.
    private struct Gathered {
        /// The entries mapped to each record, by key.
        var entries: [String: [MappedEntry]] = [:]
        /// The regions attached to types and files.
        var attachments = CoverageAttachments()
        /// The unmapped entries, before demangling.
        var unmapped: [CoverageUnmapped] = []
        /// Each kept file's skipped ranges.
        var skipped: [String: Set<CoverageLineRange>] = [:]
        /// Where kept files hold saturated counts.
        var saturated: Set<CoverageSaturation> = []
    }

    /// The rule the `map:` option records: what changes it changes the
    /// figures.
    static let rule = "kept = scanned production files; entries by regions[0] start (line, column) to the "
        + "innermost record, top-level entry by statement lines; closures folded; regions deduplicated by "
        + "range, max count; record lines by llvm-cov's per-function line rule over the record's regions, "
        + "minus wrap-only lines in nested records; file lines by llvm-cov's file line rule"
    /// A record's reason when no test bundle has code for it.
    static let noData = "no coverage data"
    /// A record's reason when none of its module's files is in the export.
    static let notLinked = "not linked into any test bundle"
    /// An entry's reason when it spans several files or holds an expansion.
    static let expansion = "macro or expansion region"
    /// An entry's reason when it has no code region.
    static let noCode = "no code region"

    /// The scan's production records, by key.
    private let records: [FunctionRecord]
    /// Keys of the subscripts whose accessors carry the coverage.
    private let containers: Set<String>
    /// Sorts the export's files.
    private let classifier: CoverageFileClassifier
    /// Places entries.
    private let placement: PositionPlacement
    /// Links public functions to their tests.
    private let links: CoverageTestLinks

    /// A mapper onto `measured`, the package at `root` with `targets`,
    /// whose configuration excludes `excluded`; the coverage run skipped
    /// the tests `skipPatterns` (its `--skip` regexes) match.
    init(
        measured: ScanMeasurements,
        targets: [TargetSummary],
        root: URL,
        excluded: [GlobPattern],
        skipPatterns: [String]
    ) {
        records = measured.records.filter { $0.role == .production }.sorted { $0.key < $1.key }
        let parents = Set(records.filter { $0.kind == .accessor }.compactMap(\.parentKey))
        containers = Set(records.filter { $0.kind == .subscriptDeclaration && parents.contains($0.key) }.map(\.key))
        classifier = CoverageFileClassifier(
            root: root,
            build: StoreLocation.directoryName + "/" + CoverageAdapter.buildDirectory,
            targets: targets,
            parsed: Set(measured.files.map(\.path)),
            excluded: excluded
        )
        placement = PositionPlacement(measured: measured)
        links = CoverageTestLinks(measured: measured, containers: containers, skipPatterns: skipPatterns)
    }

    /// The places in `file` where `counts` (by line) are saturated.
    private static func saturation(_ counts: [(line: Int, count: Int64)], in file: String) -> [CoverageSaturation] {
        counts.filter { CoverageCount.isSaturated($0.count) }.map { CoverageSaturation(file: file, line: $0.line) }
    }

    /// Whether `function` is the top-level entry of `module`'s executable.
    private static func isTopLevelEntry(_ function: CoverageExportFunction, module: String) -> Bool {
        function.name == "\(CoverageBundles.moduleName(of: module))_main" || function.name == "main"
    }

    /// Unmapped entries by file, then position, then name.
    private static func unmappedOrder(_ lhs: CoverageUnmapped, _ rhs: CoverageUnmapped) -> Bool {
        (lhs.file, lhs.startLine, lhs.startColumn, lhs.name) < (rhs.file, rhs.startLine, rhs.startColumn, rhs.name)
    }

    /// How many of the files of `classes` were dropped, by why.
    private static func dropped(_ classes: [PackageFileClass]) -> CoverageDropped {
        CoverageDropped(
            build: classes.count { $0 == .build },
            outsideRoot: classes.count { $0 == .outsideRoot },
            testFiles: classes.count { $0 == .testFile },
            otherPackage: classes.count { $0 == .otherPackage },
            otherLanguage: classes.count { $0 == .otherLanguage }
        )
    }

    /// The modules of the production files among `classes`, kept or not.
    private static func linkedModules(_ classes: [PackageFileClass]) -> Set<String> {
        Set(classes.compactMap { fileClass -> String? in
            switch fileClass {
            case let .kept(_, module), let .unmapped(_, module, _):
                return module

            case .build, .outsideRoot, .testFile, .otherPackage, .otherLanguage:
                return nil
            }
        })
    }

    /// The unmapped entry `function` of `path`, for `reason`.
    private static func unmapped(_ function: CoverageExportFunction, path: String, reason: String) -> CoverageUnmapped {
        let first = function.regions.first
        return CoverageUnmapped(
            file: path,
            startLine: first?.start.line ?? 0,
            startColumn: first?.start.column ?? 0,
            endLine: first?.end.line ?? 0,
            endColumn: first?.end.column ?? 0,
            count: function.count,
            name: function.name,
            demangled: nil,
            reason: reason
        )
    }

    /// `export` mapped, with `profiles`' bundles, test outcome and
    /// per-target counts; `demangle` demangles the unmapped entries' names.
    func report(
        of export: CoverageExport,
        profiles: CoverageProfiles,
        demangle: ([String]) -> [String: String]
    ) -> CoverageReport {
        var classes: [String: PackageFileClass] = [:]
        for filename in export.files.map(\.filename) + export.functions.compactMap(\.filenames.first)
        where classes[filename] == nil {
            classes[filename] = classifier.classify(filename)
        }
        var gathered = Gathered()
        for function in export.functions {
            if let filename = function.filenames.first, let fileClass = classes[filename] {
                gather(function, fileClass: fileClass, into: &gathered)
            }
        }
        var fileLines: [String: [CoverageLineIterator.Line]] = [:]
        for file in export.files {
            if case let .kept(path, _) = classes[file.filename] {
                fileLines[path] = CoverageLineIterator.lines(of: file.segments)
                let counts = file.segments.map { (line: $0.line, count: $0.executionCount) }
                gathered.saturated.formUnion(Self.saturation(counts, in: path))
            }
        }
        let kept = fileLines.keys.sorted()
        let fileClasses = export.files.compactMap { classes[$0.filename] }
        let linked = Self.linkedModules(Array(classes.values))
        let names = demangle(gathered.unmapped.map(\.name).sorted())
        return CoverageReport(
            records: records.map { record in
                coverage(of: record, entries: gathered.entries[record.key] ?? [], profiles: profiles, linked: linked)
            },
            attachments: gathered.attachments.attachments(fileLines: fileLines, kept: kept, placement: placement),
            unmapped: gathered.unmapped.map { $0.with(demangled: names[$0.name]) }.sorted(by: Self.unmappedOrder),
            dropped: Self.dropped(fileClasses),
            bundles: profiles.bundles,
            tests: profiles.testStatus == 0 ? "passed" : "failing",
            saturated: gathered.saturated.sorted { ($0.file, $0.line) < ($1.file, $1.line) },
            files: kept.map { path in
                CoverageFileLines(
                    file: path,
                    lines: CoverageFileRuns.runs(of: fileLines[path] ?? []),
                    skipped: (gathered.skipped[path] ?? []).sorted { ($0.start, $0.end) < ($1.start, $1.end) }
                )
            }
        )
    }

    /// Adds where `function`, in a file of `fileClass`, goes to `gathered`.
    private func gather(
        _ function: CoverageExportFunction,
        fileClass: PackageFileClass,
        into gathered: inout Gathered
    ) {
        let path: String
        let module: String
        switch fileClass {
        case let .unmapped(file, _, reason):
            gathered.unmapped.append(Self.unmapped(function, path: file, reason: reason))
            return

        case let .kept(file, owner):
            path = file
            module = owner

        case .build, .outsideRoot, .testFile, .otherPackage, .otherLanguage:
            return
        }
        let counts = function.regions.map { (line: $0.start.line, count: $0.executionCount) }
        gathered.saturated.formUnion(Self.saturation(counts, in: path))
        let skipped = function.regions.filter(\.isSkipped)
        gathered.skipped[path, default: []].formUnion(skipped.map { region in
            CoverageLineRange(start: region.start.line, end: region.end.line)
        })
        let isExpansion = function.filenames.count > 1 || function.regions.contains { region in
            region.fileID != 0 || region.expandedFileID != 0 || region.kind == CoverageRegion.expansionKind
        }
        let code = function.regions.filter(\.isCode)
        guard isExpansion == false, let anchor = code.first else {
            let reason = isExpansion ? Self.expansion : Self.noCode
            gathered.unmapped.append(Self.unmapped(function, path: path, reason: reason))
            return
        }
        let entry = MappedEntry(name: function.name, regions: code, skipped: skipped)
        if Self.isTopLevelEntry(function, module: module), let topLevel = placement.topLevelRecord(in: path) {
            gatherTopLevel(function, entry: entry, record: topLevel, path: path, into: &gathered)
            return
        }
        switch placement.place(at: anchor.start, end: anchor.end, in: path) {
        case .record(let key):
            gathered.entries[key, default: []].append(entry)

        case .type(let owner):
            gathered.attachments.attach(code, in: path, to: .type, owner: owner)

        case .file:
            gathered.attachments.attach(code, in: path, to: .file, owner: path)

        case .unmapped(let reason):
            gathered.unmapped.append(Self.unmapped(function, path: path, reason: reason))
        }
    }

    /// Adds where `function`, the top-level entry `entry` of the file at
    /// `path`, goes to `gathered`: its regions starting on statement lines
    /// to `record`, the file's top-level-code record, unless there are
    /// none (null, never 0 of 0); the rest to the file; and the statement
    /// lines none of its regions spans as skipped ranges.
    private func gatherTopLevel(
        _ function: CoverageExportFunction,
        entry: MappedEntry,
        record: FunctionRecord,
        path: String,
        into gathered: inout Gathered
    ) {
        let statements = placement.statementLines(in: path)
        let own = entry.regions.filter { statements.contains($0.start.line) }
        if own.isEmpty == false {
            gathered.entries[record.key, default: []]
                .append(MappedEntry(name: entry.name, regions: own, skipped: entry.skipped))
        }
        let uncompiled = statements.filter { line in
            function.regions.contains { $0.start.line <= line && line <= $0.end.line } == false
        }
        gathered.skipped[path, default: []].formUnion(CoverageLineRange.ranges(covering: uncompiled))
        let globals = entry.regions.filter { statements.contains($0.start.line) == false }
        gathered.attachments.attach(globals, in: path, to: .file, owner: path)
    }

    /// `record`'s coverage from `entries`, the test targets ran by
    /// `profiles`' counts, and for a public function its link rule and
    /// linked tests; with none, a container's empty figures or the reason,
    /// `linked` naming the modules with files in the export.
    private func coverage(
        of record: FunctionRecord,
        entries: [MappedEntry],
        profiles: CoverageProfiles,
        linked: Set<String>
    ) -> CoverageRecord {
        let link = links.link(of: record)
        guard entries.isEmpty == false else {
            let reason: String? = containers.contains(record.key)
                ? nil
                : (linked.contains(record.module) ? Self.noData : Self.notLinked)
            return CoverageRecord(
                key: record.key,
                lines: nil,
                regions: nil,
                testTargets: [],
                reason: reason,
                link: link,
                linkedTests: nil
            )
        }
        let regions = CoverageRecordLines.deduplicated(entries.flatMap(\.regions))
        let nested = placement.records(in: record.file)
            .filter { other in
                other.key != record.key && record.range.start <= other.range.start
                    && other.range.end <= record.range.end
            }
            .map(placement.span(of:))
        let lines = CoverageRecordLines.lines(
            regions: regions,
            skipped: CoverageRecordLines.deduplicated(entries.flatMap(\.skipped)),
            nested: nested
        )
        let names = entries.map(\.name)
        let targets = profiles.bundles.filter { bundle in
            names.contains { name in (profiles.counts[bundle]?[name] ?? 0) > 0 }
        }
        return CoverageRecord(
            key: record.key,
            lines: CoverageRecordLines.tally(of: lines),
            regions: CoverageRecordLines.tally(of: regions),
            testTargets: targets,
            reason: nil,
            link: link,
            linkedTests: link.flatMap { links.linkedTests(of: record, link: $0, targets: targets) }
        )
    }
}
