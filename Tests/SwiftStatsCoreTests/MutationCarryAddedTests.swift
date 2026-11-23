import Foundation
@testable import SwiftStatsCore
import Testing

/// A same-tree rescan that parses more than the held scan did (M6, design
/// §6.4, as built; review finding 15): a configuration kept outside the
/// tree that no longer excludes a file, or a build extracting more
/// records, gives the rescan production records the held results never
/// mapped onto, and files whose mutants were left unmapped because they
/// weren't parsed. Carrying would keep the old placement, so the rescan is
/// refused, as M5 refuses coverage over an added record.
@Suite("Mutation carry over added records")
struct MutationCarryAddedTests {
    /// The Coverage fixture's configuration without its exclusion of
    /// `Excluded.swift`.
    private static let unexcluding = "generated:\n  - Sources/Probe/Generated.swift\n"
    /// The file the fixture's configuration excludes.
    private static let excludedPath = "Sources/Probe/Excluded.swift"

    /// The held recorded run on a clean scan, and a rescan of the same
    /// tree no longer excluding `Excluded.swift`.
    private static func scans() throws -> (held: ScannedSnapshot, rescan: ScannedSnapshot) {
        let held = try MutationCarrySamples.held(try MutationCarrySamples.scan(git: MutationCarrySamples.clean))
        let rescan = try MutationCarrySamples.scan(
            git: MutationCarrySamples.clean,
            files: [".swiftstats.yml": unexcluding],
            date: MutationCarrySamples.later(1)
        )
        return (held, rescan)
    }

    @Test("""
        a rescan of the same tree that no longer excludes a file is refused, writing nothing, naming the record \
        the held results never mapped onto
        """)
    func unexcludedRecord() throws {
        let (package, workspace) = try CarrySamples.store()
        defer { package.remove() }
        let (held, rescan) = try Self.scans()
        let helper = try MutationCarrySamples.key("excludedHelper", in: rescan)
        let excluded = try #require(held.report.mutation).mutants.filter { $0.path == Self.excludedPath }
        #expect(held.report.records.contains { $0.key == helper } == false)
        #expect(excluded.isEmpty == false && excluded.allSatisfy { $0.place == .unmapped })

        let result = try MutationCarrySamples.refusal(in: workspace, held: held, rescan: rescan)

        #expect(result.error == MutationCarrySamples.refused("`\(helper)` has no mutation results"))
        #expect(result.kept)
    }

    @Test("""
        a held mutant left unmapped because its file wasn't parsed refuses a rescan that parses that file, even \
        when every record the rescan has was held
        """)
    func unparsedFile() throws {
        let (held, rescan) = try Self.scans()
        let results = try #require(held.report.mutation)
        let stored = HeldMutation(
            git: MutationCarrySamples.clean,
            run: MutationCarrySamples.run,
            results: StoredMutation(report: results),
            warnings: [],
            spans: MutationCarrySamples.spans(of: rescan)
        )
        let reason = "`\(Self.excludedPath)` is scanned now, but its mutants weren't mapped"

        #expect(MutationCarry.refusal(of: stored, onto: rescan) == reason)
        #expect(MutationCarry.unparsedRefusal(of: results.mutants, onto: held.report.files) == nil)
    }
}
