//
//  CouplingSignalHarness+Snapshot.swift
//  SwiftStatsCoreTests
//
//  What `CouplingSignalHarness` gives its scan: index results with a USR
//  shaped as Swift mangles one on every record but `unseen()` (none) and
//  `bridged()` (a `c:` one), the package's production types with USRs of
//  that shape and the family references a test gives; a history holding
//  the test's pairs, cut at a `coupling.min_support` of 3; and the signal
//  and its verdicts read from the stored snapshot.
//

@testable import SwiftStatsCore
import Testing

extension CouplingSignalHarness {
    /// A family reference by short names.
    static func reference(
        _ from: String,
        _ destination: String,
        _ via: IndexFamilyReference.Via
    ) -> IndexFamilyReference {
        IndexFamilyReference(fromFamily: from, toFamily: destination, via: via)
    }

    /// A family type reference from the family named `family` to the
    /// type `typePath` of `module`.
    static func typeReference(_ family: String, _ module: String, _ typePath: String) -> IndexFamilyTypeReference {
        IndexFamilyTypeReference(family: family, module: module, typePath: typePath, typeFile: nil)
    }

    /// `name` as a mangled identifier: its length, then itself.
    private static func identifier(_ name: String) -> String {
        "\(name.count)\(name)"
    }

    /// The USR of the struct `typePath` of `module`, shaped as Swift
    /// mangles one: the module, then each part of the path, each followed
    /// by `V`.
    static func typeUSR(_ module: String, _ typePath: String) -> String {
        "s:" + identifier(module) + typePath.split(separator: ".").map { identifier(String($0)) + "V" }.joined()
    }

    /// The USR of `record`, shaped as Swift mangles one: its context's
    /// (the type its extension's head means, then its own module and `E`,
    /// for an extension member; its type; else its module), then its name
    /// and a function type; `bridged()` has a `c:` USR.
    private static func usr(of record: FunctionRecord) -> String {
        let function = identifier(record.name) + "SiyF"
        if record.name == "bridged" {
            return "c:objc(cs)Shared(im)bridged"
        }
        if let (module, typePath) = extended[record.name] {
            return typeUSR(module, typePath) + identifier(record.module) + "E" + function
        }
        guard let typePath = record.typePath else {
            return "s:" + identifier(record.module) + function
        }
        return typeUSR(record.module, typePath) + function
    }

    /// Each record of `scanned` with its USR (`usr(of:)`), but `unseen()`,
    /// which has none (an inactive `#if` branch).
    private static func records(of scanned: ScannedSnapshot) -> [IndexRecordUSR] {
        scanned.report.records.map { record in
            let seen = record.name != "unseen"
            return IndexRecordUSR(
                key: record.key,
                usr: seen ? usr(of: record) : nil,
                usrAccessor: nil,
                reason: seen ? nil : .inactiveIfBranch,
                coupling: seen
                    ? IndexRecordCoupling(
                        witness: false,
                        references: IndexReferences(sameModule: 0, otherModules: 0, tests: 0, testReferrers: [])
                    )
                    : nil
            )
        }
    }

    /// The index results of `scanned` with `facts`' references.
    static func index(of scanned: ScannedSnapshot, facts: Facts) throws -> IndexReport {
        let keys = Dictionary(scanned.report.records.map { ($0.name, $0.key) }) { first, _ in first }
        let named = { (name: String) in keys[name] ?? name }
        let shell = try IndexStoreSamples.index(records: [])
        return IndexReport(
            store: shell.store,
            libraryModules: [],
            records: records(of: scanned),
            definitions: shell.definitions,
            disagreements: [],
            withoutRecord: [],
            collisions: [],
            moduleEdges: [],
            types: types.map { type in
                IndexTypeRow(
                    module: type.0,
                    typePath: type.1,
                    typeFile: typeFiles["\(type.0) \(type.1)"],
                    usr: typeUSR(type.0, type.1),
                    referrersSameModule: 0,
                    referrersOtherModules: 0,
                    referrersTests: 0,
                    cycle: nil
                )
            },
            familyReferences: facts.references.map { reference in
                IndexFamilyReference(
                    fromFamily: named(reference.fromFamily),
                    toFamily: named(reference.toFamily),
                    via: reference.via
                )
            },
            familyTypeReferences: facts.typeReferences.map { reference in
                IndexFamilyTypeReference(
                    family: named(reference.family),
                    module: reference.module,
                    typePath: reference.typePath,
                    typeFile: reference.typeFile
                )
            },
            files: []
        )
    }

    /// `scanned` holding `index` and a history with `facts.pairs`, its
    /// history and index runs ran unless `facts.missing` names one.
    static func snapshot(
        _ scanned: ScannedSnapshot,
        index: IndexReport,
        facts: Facts
    ) throws -> ScannedSnapshot {
        let shell = try IndexStoreSamples.history(commit: "c1")
        let history = HistoryReport(
            commit: shell.commit,
            date: shell.date,
            windowDays: shell.windowDays,
            windowStart: shell.windowStart,
            mergeStyle: shell.mergeStyle,
            commits: shell.commits,
            windowCommits: shell.windowCommits,
            commitLog: [],
            fixCommits: [],
            revertCommits: [],
            sweepCommits: [],
            families: [],
            coupling: facts.pairs,
            warnings: []
        )
        let historyRun = CollectorRunInfo(
            name: HistoryCollector.name,
            state: .ran,
            reason: nil,
            version: "test",
            identity: nil,
            identityLabel: nil,
            options: ["window: 365d", "coupling.min_support: \(minimumSupport)"],
            durationMilliseconds: 0
        )
        var report = scanned.report
        var info = scanned.info
        if facts.missing != HistoryCollector.name {
            report = report.with(history: history, status: historyRun.status)
            info = info.with(run: historyRun)
        }
        if facts.missing != IndexAdapter.name {
            let indexRun = IndexStoreSamples.run(IndexAdapter.name, .ran)
            report = report.with(index: IndexRows.normalized(index), status: indexRun.status)
            info = info.with(run: indexRun)
        }
        return ScannedSnapshot(info: info, report: report)
    }

    /// Hidden coupling over `snapshot`, with `thresholds`.
    static func signal(_ snapshot: StoredSnapshot, thresholds: SignalThresholds) throws -> SignalResult {
        try #require(
            SignalEngine.signals(of: SignalInputs(snapshot: snapshot), thresholds: thresholds)
                .first { $0.name == .hiddenCoupling }
        )
    }

    /// What the signal decides of each of `snapshot`'s pairs, in order,
    /// with `thresholds`.
    static func verdicts(
        _ snapshot: StoredSnapshot,
        thresholds: SignalThresholds
    ) throws -> [HiddenCoupling.Verdict] {
        let index = try #require(snapshot.index?.report)
        return HiddenCoupling.judged(
            snapshot,
            pairs: snapshot.couplingPairs,
            index: index,
            limits: HiddenCoupling.Limits(thresholds)
        )
        .map(\.verdict)
    }
}
