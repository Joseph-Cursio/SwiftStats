import Foundation
@testable import SwiftStatsCore
import Testing

/// Why held T1 results don't carry onto a rescan of the same tree (M7,
/// design §9.4), rule by rule and family by family, on hand-made snapshots
/// of a small package: each of the eight rules the results were collected
/// under refuses on its own when the held run lacks it; so does a family
/// the held family or family-type references name that the rescan's
/// records, grouped by this build, don't have, as a rebuild that regroups
/// families without changing a rule gives it; and so does a record whose
/// file-scoped owning type's file alone changed (`IndexCarryRefusalTests`
/// covers the order of the conditions and the other record, type and file
/// changes).
@Suite("Index carry refusals by rule, family and file-scoped owner")
struct IndexCarryRulesTests {
    /// The rules design §9.4 lists, each with the collector whose options
    /// name it.
    static let rules = [
        (BuildAdapter.name, "map: " + TimingMapper.rule),
        (BuildAdapter.name, "warnings: " + WarningReader.rule),
        (IndexAdapter.name, "units: " + UnitFilter.rule),
        (IndexAdapter.name, "usr: " + USRJoin.rule),
        (IndexAdapter.name, "references: " + ReferenceGraph.rule),
        (IndexAdapter.name, "types: " + TypeOwnership.rule),
        (PeripheryAdapter.name, "classes: " + PeripheryOutput.rule),
        (PeripheryAdapter.name, "map: " + DeadCodeMapper.rule)
    ]

    /// `held` with `index` as its index results.
    private static func replacing(index: IndexReport, in held: HeldIndex) -> HeldIndex {
        HeldIndex(
            git: held.git,
            build: held.build,
            readers: held.readers,
            collectedAt: held.collectedAt,
            buildReport: held.buildReport,
            typeCheckTotals: held.typeCheckTotals,
            index: index,
            deadCode: held.deadCode,
            findings: held.findings,
            warnings: held.warnings,
            records: held.records,
            types: held.types,
            files: held.files
        )
    }

    /// `index` with its family references and family-type references
    /// replaced by `references` and `typeReferences`.
    private static func replacing(
        references: [IndexFamilyReference],
        typeReferences: [IndexFamilyTypeReference],
        in index: IndexReport
    ) -> IndexReport {
        IndexReport(
            store: index.store,
            libraryModules: index.libraryModules,
            records: index.records,
            definitions: index.definitions,
            disagreements: index.disagreements,
            withoutRecord: index.withoutRecord,
            collisions: index.collisions,
            moduleEdges: index.moduleEdges,
            types: index.types,
            familyReferences: references,
            familyTypeReferences: typeReferences,
            files: index.files
        )
    }

    /// Why `held` can't be carried onto `plain`, a rescan of the same tree.
    private static func refusal(of held: HeldIndex, onto plain: ScannedSnapshot) -> String? {
        IndexCarrySamples.refusal(
            of: held,
            onto: plain,
            records: plain.report.records,
            types: plain.report.types,
            files: plain.report.files
        )
    }

    @Test(
        """
        a held run of a collector that ran whose options lack only one of the eight rules refuses the carry, \
        naming the collector and the rule's lead
        """,
        arguments: rules
    )
    func eachRule(collector: String, option: String) throws {
        let plain = try IndexCarrySamples.scan(git: IndexCarrySamples.clean, date: SnapshotHarness.date)
        let held = try IndexCarrySamples.held(of: try IndexCarrySamples.held(plain))
        let run = try #require(held.runs.first { $0.name == collector })
        let lacking = CollectorRunInfo(
            name: run.name,
            state: run.state,
            reason: run.reason,
            version: run.version,
            identity: run.identity,
            identityLabel: run.identityLabel,
            options: run.options.filter { $0 != option },
            durationMilliseconds: run.durationMilliseconds
        )
        let lead = option.prefix { $0 != " " }

        let refused = Self.refusal(of: IndexCarrySamples.replacing(runs: [lacking], in: held), onto: plain)

        #expect(run.state == .ran && run.options.contains(option))
        #expect(Self.refusal(of: held, onto: plain) == nil)
        #expect(refused == "`\(collector)` was collected under another `\(lead)` rule")
    }

    @Test("""
        a family named by a held family reference, at either end, or by a held family-type reference that isn't a \
        family of the rescan's records refuses the carry, naming the first such family in order
        """)
    func otherFamilies() throws {
        let plain = try IndexCarrySamples.scan(git: IndexCarrySamples.clean, date: SnapshotHarness.date)
        let held = try IndexCarrySamples.held(of: try IndexCarrySamples.held(plain))
        let index = try #require(held.index)
        let families = Set(HeldIndex.places(of: plain.report.records).values.map(\.family))
        let reference = try #require(index.familyReferences.first)
        let typeReference = try #require(index.familyTypeReferences.first)
        let older = "Lib::Box::regrouped"
        let oldest = "Lib::Box::earlier"
        let carry = { (references: [IndexFamilyReference], typeReferences: [IndexFamilyTypeReference]) in
            Self.refusal(
                of: Self.replacing(
                    index: Self.replacing(references: references, typeReferences: typeReferences, in: index),
                    in: held
                ),
                onto: plain
            )
        }
        let from = IndexFamilyReference(fromFamily: older, toFamily: reference.toFamily, via: reference.via)
        let destination = IndexFamilyReference(fromFamily: reference.fromFamily, toFamily: older, via: reference.via)
        let typed = IndexFamilyTypeReference(
            family: older,
            module: typeReference.module,
            typePath: typeReference.typePath,
            typeFile: typeReference.typeFile
        )
        let both = IndexFamilyReference(fromFamily: older, toFamily: oldest, via: reference.via)
        let refused = "family `\(older)` is gone now"

        let named = index.familyReferences.flatMap { [$0.fromFamily, $0.toFamily] }
            + index.familyTypeReferences.map(\.family)
        #expect(named.isEmpty == false && named.allSatisfy(families.contains))
        #expect(carry(index.familyReferences, index.familyTypeReferences) == nil)
        #expect(carry([from], index.familyTypeReferences) == refused)
        #expect(carry([destination], index.familyTypeReferences) == refused)
        #expect(carry(index.familyReferences, [typed]) == refused)
        #expect(carry([both], [typed]) == "family `\(oldest)` is gone now")
    }

    @Test("""
        a record whose owning type is now file-scoped, its type path the same, refuses the carry as owned by \
        another type
        """)
    func fileScopedOwner() throws {
        let plain = try IndexCarrySamples.scan(git: IndexCarrySamples.clean, date: SnapshotHarness.date)
        let held = try IndexCarrySamples.held(of: try IndexCarrySamples.held(plain))
        let open = try IndexCarrySamples.record("open", in: plain)
        let scoped = IndexCarrySamples.records(of: plain, changing: open.key) { record in
            var changed = record
            changed.typeFile = record.file
            return changed
        }

        let refused = IndexCarrySamples.refusal(
            of: held,
            onto: plain,
            records: scoped,
            types: plain.report.types,
            files: plain.report.files
        )

        #expect(open.typePath == "Box" && open.typeFile == nil)
        #expect(refused == "`\(open.key)` belongs to another type now")
    }
}
