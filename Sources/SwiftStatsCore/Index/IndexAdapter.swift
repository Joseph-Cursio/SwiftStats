//
//  IndexAdapter.swift
//  SwiftStatsCore
//
//  The `index` collector (M7, design §2–§4): it reads the index store the
//  T1 build wrote, in process, through indexstore-db's `IndexStore`
//  reader, for the records' USRs, references and coupling. It runs only
//  with the T1 group (`scan --index`, `BuildAdapter`), and, linked rather
//  than run, takes no `path`. A run locates the toolchain's
//  `libIndexStore.dylib` and the store, opens it through the scanner's
//  factory, walks it (`IndexWalk`, classing units with `UnitFilter`),
//  moves stale and other-module units out of the store, joins the
//  definitions to the records (`USRJoin`), gives each record without a
//  USR its reason (`USRReason`), and counts the references, module edges,
//  types and cycles (`IndexCoupling`). Nothing is partial: anything that
//  doesn't read fails the collector, its reason free of absolute paths.
//

import Foundation

/// The `index` collector.
enum IndexAdapter {
    /// What a run of the collector gave.
    struct Run {
        /// Its result and run time.
        let timed: TimedAdapterResult
        /// The index results mapped onto the scan; nil unless it ran.
        let report: IndexReport?
    }

    /// What a read of the store needs from the scan.
    struct Scan {
        /// The package root.
        let root: URL
        /// The scan's records, in its record order.
        let records: [FunctionRecord]
        /// The scan's type records.
        let types: [TypeRecord]
        /// The scanned files.
        let files: [FileRecord]
        /// The scanned targets.
        let targets: [TargetSummary]
        /// Each file's top-level statement lines, by path.
        let topLevelLines: [String: Set<Int>]
        /// Each file's `private` and `fileprivate` types, as dotted paths,
        /// by path.
        let fileScopedTypes: [String: Set<String>]
        /// The scan's warnings, which name its key collisions.
        let warnings: [ScanWarning]
    }

    /// A read that can't go on.
    struct Failure: Error, CustomStringConvertible {
        /// Why, for the collector's reason.
        let description: String
    }

    /// The collector's name in a snapshot and in `.swiftstats.yml`.
    static let name = "index"
    /// The collector's options, in order (design §1.8): the reader, where
    /// `libIndexStore.dylib` comes from, and each mapping's rule.
    static let options = [
        "reader: indexstore-db IndexStore " + IndexStoreReader.pinned.prefix(shortPinLength),
        "libIndexStore: toolchain",
        "units: " + UnitFilter.rule,
        "usr: " + USRJoin.rule,
        "references: " + ReferenceGraph.rule,
        "types: " + TypeOwnership.rule
    ]
    /// Why the collector fails when the store holds none of the package's
    /// units while the scan has records in targets the build compiles.
    static let noUnitsReason = "the store holds no unit of the package's targets"
    /// How many characters of the pinned revision the options name.
    private static let shortPinLength = 7
    /// The kind of target the build never compiles.
    private static let pluginType = "plugin"
    /// The product kind whose targets are library modules.
    private static let libraryKind = "library"
    /// How an Objective-C USR starts.
    private static let objcPrefix = "c:"
    /// The compiler option naming the module a task log's command compiles.
    private static let moduleNameOption = "-module-name"

    /// The collector's run over the store of the build that left
    /// `products`, for `scan`, opened by `factory`: ran with its results,
    /// or failed, saying why.
    static func run(
        products: BuildSession.Products,
        scan: Scan,
        opening factory: (_ store: URL, _ library: URL) throws -> any IndexStoreSource
    ) -> Run {
        let (outcome, milliseconds) = Stopwatch.time {
            Result { try read(products: products, scan: scan, opening: factory) }
        }
        let result: AdapterResult
        switch outcome {
        case .success:
            result = AdapterResult(
                status: CollectorStatus(
                    name: name,
                    state: .ran,
                    version: IndexStoreReader.version,
                    reason: nil,
                    options: options
                ),
                findings: [],
                warnings: []
            )

        case .failure(let error):
            let replacements = [
                (products.scratch, CoverageCommand.buildPlaceholder),
                (products.toolchain.directory, CoverageCommand.toolchainPlaceholder),
                (scan.root, CoverageCommand.packagePlaceholder)
            ]
            result = .failed(
                name,
                error: Failure(description: SwiftInferTargetRun.reason(for: error, replacing: replacements)),
                options: options
            )
        }
        return Run(
            timed: TimedAdapterResult(result: result, executable: nil, identity: nil, milliseconds: milliseconds),
            report: try? outcome.get()
        )
    }

    /// The store of `products` read for `scan`: located, opened by
    /// `factory`, walked, its stale and other-module units moved out, and
    /// its definitions joined to the records.
    private static func read(
        products: BuildSession.Products,
        scan: Scan,
        opening factory: (_ store: URL, _ library: URL) throws -> any IndexStoreSource
    ) throws -> IndexReport {
        let location = try IndexStoreLocator.locate(products)
        let source = try factory(location.store, location.library)
        let filter = try UnitFilter(
            root: IndexStoreReader.realPath(scan.root.path),
            scratch: products.scratch.path,
            package: products.package
        )
        let snapshot = try IndexWalk.walk(source, filter: filter)
        let quarantined = try filter.quarantine(snapshot)
        let plugins = Set(products.package.targets.filter { $0.type == pluginType }.map(\.name))
        if snapshot.readUnits.isEmpty, scan.records.contains(where: { plugins.contains($0.module) == false }) {
            throw Failure(description: noUnitsReason)
        }
        let changed = Set(products.changedFiles)
        let files = Set(scan.files.map(\.path))
        let join = USRJoin(snapshot: snapshot, records: scan.records, files: files, changedFiles: changed)
        let coupling = IndexCoupling(
            snapshot: snapshot,
            join: join,
            scan: scan,
            joinable: files.subtracting(changed),
            packageTargets: Set(filter.modules.values)
        )
        let evidence = USRReason.Evidence(
            pluginTargets: plugins,
            changedFiles: changed,
            definitions: join.definitionPositions,
            unitModules: Set(snapshot.units.map(\.module)),
            readFiles: readFiles(of: snapshot),
            inDisagreement: join.inDisagreement,
            compiles: compiled(scan.records, snapshot: snapshot, products: products).contains
        )
        return IndexReport(
            store: summary(of: snapshot, quarantined: quarantined.count),
            libraryModules: libraryModules(products.package, snapshot: snapshot),
            records: recordUSRs(scan.records, join: join, coupling: coupling, evidence: evidence),
            definitions: definitions(of: join),
            disagreements: join.disagreements,
            withoutRecord: join.withoutRecord,
            collisions: join.collisions(records: scan.records, warnings: scan.warnings),
            moduleEdges: coupling.moduleEdges,
            types: coupling.types,
            familyReferences: coupling.familyReferences,
            familyTypeReferences: coupling.familyTypeReferences,
            files: scan.files.map(\.path).sorted().map { IndexFileHash(path: $0, sha256: products.hashes[$0]) }
        )
    }

    /// Each of `records`' USRs from `join`, or the reason from `evidence`
    /// that it has none, with its coupling from `coupling`.
    private static func recordUSRs(
        _ records: [FunctionRecord],
        join: USRJoin,
        coupling: IndexCoupling,
        evidence: USRReason.Evidence
    ) -> [IndexRecordUSR] {
        records.map { record in
            IndexRecordUSR(
                key: record.key,
                usr: join.primary[record.key],
                usrAccessor: join.secondary[record.key],
                reason: join.primary[record.key] == nil ? USRReason.first(for: record, evidence: evidence) : nil,
                coupling: coupling.records[record.key]
            )
        }
    }

    /// What `join` counted.
    private static func definitions(of join: USRJoin) -> IndexDefinitions {
        IndexDefinitions(
            joined: join.joinedCount,
            implicit: join.implicitCount,
            secondary: join.secondary.count,
            objc: join.primary.values.count { $0.hasPrefix(objcPrefix) }
        )
    }

    /// The main files of the units `snapshot` read, by module.
    private static func readFiles(of snapshot: IndexSnapshot) -> [String: Set<String>] {
        Dictionary(grouping: snapshot.readUnits, by: \.module).mapValues { Set($0.map(\.path)) }
    }

    /// The store as `snapshot` read it, `quarantined` units moved out.
    private static func summary(of snapshot: IndexSnapshot, quarantined: Int) -> IndexStoreSummary {
        IndexStoreSummary(
            layout: IndexStoreSummary.swiftBuildLayout,
            counts: IndexUnitCounts(snapshot.units.map(\.unitClass), quarantined: quarantined),
            records: snapshot.records.count,
            occurrences: snapshot.records.reduce(0) { $0 + $1.occurrences.count },
            units: snapshot.units.filter(\.unitClass.isListed).map { unit in
                IndexUnitRow(
                    name: unit.name,
                    target: unit.module,
                    mainFile: unit.path,
                    triple: unit.triple,
                    unitClass: unit.unitClass
                )
            }
        )
    }

    /// The library-product targets of `package` whose units `snapshot`
    /// read, sorted.
    private static func libraryModules(_ package: DescribedPackage, snapshot: IndexSnapshot) -> [String] {
        let read = Set(snapshot.readUnits.map(\.module))
        return Set(package.products.filter { $0.kind == libraryKind }.flatMap(\.targets))
            .intersection(read)
            .sorted()
    }

    /// The targets of `records` that no unit of `snapshot` names but whose
    /// compile the build's task log names (`-module-name <C99 name>`); the
    /// log is read only when some target has no unit.
    private static func compiled(
        _ records: [FunctionRecord],
        snapshot: IndexSnapshot,
        products: BuildSession.Products
    ) -> Set<String> {
        let unindexed = Set(records.map(\.module)).subtracting(snapshot.units.map(\.module))
        guard unindexed.isEmpty == false, let log = try? Data(contentsOf: products.log) else {
            return []
        }
        let text = String(bytes: log, encoding: .utf8) ?? String(bytes: log, encoding: .isoLatin1) ?? ""
        let named = moduleNames(inLog: text)
        let modules = Dictionary(products.package.targets.map { ($0.name, $0.c99name) }) { first, _ in first }
        return unindexed.filter { modules[$0].map(named.contains) ?? false }
    }

    /// Every module a compile in the task log `log` names: each word
    /// following `-module-name`.
    private static func moduleNames(inLog log: String) -> Set<String> {
        var names: Set<String> = []
        for line in log.split(whereSeparator: \.isNewline) where line.contains(moduleNameOption) {
            let words = line.split(whereSeparator: \.isWhitespace)
            for (index, word) in zip(words.indices, words) where word == moduleNameOption && index + 1 < words.count {
                names.insert(String(words[index + 1]))
            }
        }
        return names
    }
}
