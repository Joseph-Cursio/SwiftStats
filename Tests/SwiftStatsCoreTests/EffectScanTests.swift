import Foundation
@testable import SwiftStatsCore
import Testing

/// Side effects in scans (PRD §7.10, §6.2, §10.1): facts joined to
/// production records, the run's summary and status, the roll-ups that
/// count them, and the configuration that turns the collector off.
@Suite("Side effects in scans")
struct EffectScanTests {
    /// A library whose `refresh()` infers its tier from `updateTotals()`'s
    /// body and whose `record(_:)`, refuted by `print`, takes its tier from
    /// its body; and a test target whose records get no facts.
    private static let files = [
        "Sources/Lib/Ledger.swift": """
        final class Ledger {
            let cache = TotalsCache()
            let rows = RowStore()
            let totalsKey = "totals"

            func updateTotals() {
                cache.upsert(totalsKey)
            }

            func refresh() {
                updateTotals()
            }

            func double(_ value: Int) -> Int {
                value * 2
            }

            func record(_ amount: Int) {
                print(amount)
                rows.insertRow(amount)
            }
        }
        """,
        "Tests/LibTests/LedgerTests.swift": """
        import Testing

        @Test func doubles() {
            #expect(Ledger().double(2) == 4)
        }

        func makeLedger() -> Ledger {
            Ledger()
        }
        """
    ]

    /// The setting that turns the collector off.
    private static let disabled = [".swiftstats.yml": "collectors:\n  swifteffectinference:\n    enabled: false\n"]

    @Test("a scan joins facts to production records only, and records the run with its pinned revision")
    func joined() throws {
        let package = try TemporaryPackage(Self.files)
        defer { package.remove() }

        let snapshot = try SnapshotHarness.scan(package, commit: "c1")
        let report = snapshot.report

        let effects = Dictionary(uniqueKeysWithValues: report.records.compactMap { record in
            record.effect.map { (record.name, $0) }
        })
        #expect(effects.keys.sorted() == ["double", "record", "refresh", "updateTotals"])
        let refresh = try #require(effects["refresh"])
        #expect(refresh.function?.inference == .unique)
        #expect(refresh.function?.inferred?.tier == .idempotent)
        #expect(refresh.function?.inferred?.via == ["calls `updateTotals()`"])
        let double = try #require(effects["double"])
        #expect(double.tier == .pure)
        #expect(double.source == .purity)
        #expect(double.function?.shape == .endomorphism)
        let record = try #require(effects["record"])
        #expect(record.tier == .nonIdempotent)
        #expect(record.source == .bodyInferred)
        #expect(record.purity == .refuted)
        #expect(report.records.filter { $0.role != .production }.allSatisfy { $0.effect == nil })
        #expect(report.records.filter { $0.role != .production }.count == 2)
        #expect(report.effects?.revision == EffectInferenceRevision.pinned)
        #expect((report.effects?.passes ?? 0) > 1)

        let status = report.collectors.first { $0.name == EffectCollector.name }
        #expect(status == CollectorStatus(
            name: EffectCollector.name,
            state: .ran,
            version: EffectInferenceRevision.pinned,
            reason: nil,
            options: EffectCollector.options
        ))
        let run = snapshot.info.collectors.first { $0.name == EffectCollector.name }
        #expect(run?.identity == "git:\(EffectInferenceRevision.pinned)")
        #expect(run?.identityLabel == nil)
        #expect(report.warnings.isEmpty)
    }

    @Test("roll-ups count tiers and purity on production scopes, never on test scopes, under the collector's name")
    func rollups() throws {
        let package = try TemporaryPackage(Self.files)
        defer { package.remove() }

        let report = try package.scan(tools: SnapshotHarness.noTools)

        let byName = Dictionary(uniqueKeysWithValues: report.rollups.map { ($0.name, $0) })
        #expect(byName["Lib"]?.effects == byName["production"]?.effects)
        let production = try #require(byName["production"]?.effects)
        // `updateTotals`, `refresh` and `double` are pure by verdict, which
        // ignores state; `record` is refuted and non_idempotent by its body.
        #expect(production.tier == ["pure": 3, "non_idempotent": 1])
        #expect(production.purity == ["pure": 3, "refuted": 1])
        #expect(byName["LibTests"].map { $0.effects == nil } == true)
        #expect(byName["tests"].map { $0.effects == nil } == true)
        let metrics = try RollupMetrics.metrics(of: try #require(byName["production"]))
        let effectMetrics = metrics.filter { $0.path.hasPrefix("effects.") }
        #expect(effectMetrics.isEmpty == false)
        #expect(effectMetrics.allSatisfy { $0.collector == EffectCollector.name })
        #expect(MetricDirection.of("effects.tier.pure") == .neutral)
    }

    @Test("replacingKeys keeps a record's side-effect facts")
    func replacingKeysKeepsFacts() throws {
        let package = try TemporaryPackage(Self.files)
        defer { package.remove() }

        let report = try package.scan(tools: SnapshotHarness.noTools)
        let record = try #require(report.records.first { $0.name == "refresh" })
        let renamed = record.replacingKeys(key: record.key + " #2", parentKey: nil)

        #expect(renamed.effect == record.effect)
        #expect(renamed.effect != nil)
    }

    @Test("declarations whose keys collide each get their own facts under their disambiguated keys")
    func collidingKeys() throws {
        // The same signature in two files, which the compiler would reject:
        // the keys collide and the scan disambiguates them by file.
        let package = try TemporaryPackage([
            "Sources/Lib/Plain.swift": """
            func step(_ value: Int) -> Int {
                value + 1
            }
            """,
            "Sources/Lib/Noisy.swift": """
            func step(_ value: Int) -> Int {
                print(value)
                return value + 1
            }
            """
        ])
        defer { package.remove() }

        let report = try package.scan(tools: SnapshotHarness.noTools)

        let twins = Dictionary(uniqueKeysWithValues: report.records.filter { $0.name == "step" }.map { ($0.key, $0) })
        #expect(twins.keys.sorted() == [
            "Lib::func step(_: Int) -> Int @ Sources/Lib/Noisy.swift",
            "Lib::func step(_: Int) -> Int @ Sources/Lib/Plain.swift"
        ])
        #expect(twins["Lib::func step(_: Int) -> Int @ Sources/Lib/Plain.swift"]?.effect?.purity == .pure)
        #expect(twins["Lib::func step(_: Int) -> Int @ Sources/Lib/Noisy.swift"]?.effect?.purity == .refuted)
        #expect(report.warnings.map(\.message) == [
            "key shared by several declarations, disambiguated by location: Lib::func step(_: Int) -> Int"
        ])
    }

    @Test("the Side effects section says how many passes body inference took, in the singular for one")
    func passesWording() throws {
        let pure = "func double(_ value: Int) -> Int { value * 2 }\n"
        let single = try TemporaryPackage(["Sources/Lib/Math.swift": pure])
        defer { single.remove() }
        let several = try TemporaryPackage(Self.files)
        defer { several.remove() }

        let one = try single.scan(tools: SnapshotHarness.noTools)
        let many = try several.scan(tools: SnapshotHarness.noTools)

        #expect(one.effects?.passes == 1)
        #expect(MarkdownEffects.render(one).first?.hasSuffix("body inference settled in 1 pass.") == true)
        let passes = try #require(many.effects?.passes)
        #expect(passes > 1)
        #expect(MarkdownEffects.render(many).first?.hasSuffix("body inference settled in \(passes) passes.") == true)
    }

    @Test("collectors.swifteffectinference.enabled: false skips the collector, says why and leaves out its results")
    func disabled() throws {
        let package = try TemporaryPackage(Self.files.merging(Self.disabled) { $1 })
        defer { package.remove() }

        let snapshot = try SnapshotHarness.scan(package, commit: "c1")
        let report = snapshot.report

        let status = report.collectors.first { $0.name == EffectCollector.name }
        #expect(status == CollectorStatus(
            name: EffectCollector.name,
            state: .skipped,
            version: nil,
            reason: "disabled by collectors.swifteffectinference.enabled",
            options: []
        ))
        #expect(snapshot.info.collectors.first { $0.name == EffectCollector.name }?.identity == nil)
        #expect(report.records.allSatisfy { $0.effect == nil })
        #expect(report.effects == nil)
        #expect(report.rollups.allSatisfy { $0.effects == nil })
        #expect(report.warnings.isEmpty)
        let section = MarkdownEffects.render(report)
        #expect(section == ["Not collected: skipped, disabled by collectors.swifteffectinference.enabled."])
    }

    @Test("collectors.swifteffectinference takes enabled and options but no path, since SwiftStats runs it itself")
    func configuration() throws {
        let text = "collectors:\n  swifteffectinference:\n    enabled: false\n    options: [x]\n"
        let configuration = try SwiftStatsConfiguration.parse(text, path: "c.yml")

        #expect(configuration.collectors[EffectCollector.name] == CollectorSettings(enabled: false, path: nil))
        #expect(configuration.unusedKeys == ["collectors.swifteffectinference.options"])
        let withPath = "collectors:\n  swifteffectinference:\n    path: tools/sei\n"
        let message = "`collectors.swifteffectinference.path`: a collector SwiftStats runs itself has no path"
        #expect(throws: ScanError.configurationInvalid("c.yml", message)) {
            try SwiftStatsConfiguration.parse(withPath, path: "c.yml")
        }
    }
}
