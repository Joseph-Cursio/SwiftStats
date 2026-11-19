import Foundation
@testable import SwiftStatsCore
import Testing

/// M3's hand labels (PRD §11 M3 done-when 1, §13): the top 20 hotspots of
/// two repositories, judged worth attention or not, and a sample of each
/// repository's commits, judged fixes or not. `Scripts/label-sample.py`
/// writes the files with empty labels.
@Suite("Label fixtures")
struct LabelFixtureTests {
    /// One labelled hotspot.
    private struct HotspotItem: Decodable {
        let rank: Int
        let family: String
        let file: String
        let label: String?
    }

    /// A repository's labelled hotspots.
    private struct HotspotLabels: Decodable {
        let repo: String
        let packagePath: String
        let commit: String
        let items: [HotspotItem]
    }

    /// One labelled commit.
    private struct FixCommit: Decodable {
        let commit: String
        let matched: Bool
        let excluded: String?
        let label: String?
    }

    /// A repository's labelled commit sample.
    private struct FixLabels: Decodable {
        let repo: String
        let commits: [FixCommit]
    }

    /// The labelled repositories.
    private static let repositories = ["SwiftInferProperties", "SwiftProjectLintRules"]
    /// The hotspots labelled per repository.
    private static let labelledHotspots = 20
    /// The hotspots that must be judged worth attention (done-when 1).
    private static let worthNeeded = 12

    /// The fixtures directory.
    private static let fixtures = URL(fileURLWithPath: #filePath)
        .deletingLastPathComponent().deletingLastPathComponent().appendingPathComponent("Fixtures")

    /// The decoded fixture `name` in `folder`.
    private static func load<Value: Decodable>(_ folder: String, _ name: String) throws -> Value {
        let url = fixtures.appendingPathComponent(folder).appendingPathComponent("\(name).json")
        return try JSONDecoder().decode(Value.self, from: Data(contentsOf: url))
    }

    @Test(
        "each repository has 20 hotspots to label, and once labelled at least 12 are worth attention",
        arguments: repositories
    )
    func hotspots(_ name: String) throws {
        let labels: HotspotLabels = try Self.load("HotspotLabels", name)

        #expect(labels.items.map(\.rank) == Array(1...Self.labelledHotspots))
        #expect(labels.items.allSatisfy { [nil, "worth", "not-worth"].contains($0.label) })
        let labelled = labels.items.compactMap(\.label)
        guard labelled.count == labels.items.count else {
            return
        }
        #expect(labelled.filter { $0 == "worth" }.count >= Self.worthNeeded)
    }

    @Test(
        "each repository's commit sample is labelled fix or not-fix, and its precision can be computed",
        arguments: repositories
    )
    func fixes(_ name: String) throws {
        let labels: FixLabels = try Self.load("FixLabels", name)

        #expect(labels.commits.isEmpty == false)
        #expect(labels.commits.allSatisfy { [nil, "fix", "not-fix"].contains($0.label) })
        #expect(Set(labels.commits.map(\.commit)).count == labels.commits.count)
        let counted = labels.commits.filter { $0.matched && $0.excluded == nil }
        guard labels.commits.allSatisfy({ $0.label != nil }), counted.isEmpty == false else {
            return
        }
        let precision = Double(counted.filter { $0.label == "fix" }.count) / Double(counted.count)
        #expect((0...1).contains(precision))
    }

    @Test(
        "the labelled commit's top 20 hotspots are recomputed from the repository (SWIFTSTATS_LABEL_REPOS=1)",
        .enabled(if: ProcessInfo.processInfo.environment["SWIFTSTATS_LABEL_REPOS"] == "1"),
        arguments: repositories
    )
    func recompute(_ name: String) throws {
        let labels: HotspotLabels = try Self.load("HotspotLabels", name)
        let home = FileManager.default.homeDirectoryForCurrentUser
        let folder = labels.repo == "SwiftProjectLintRules" ? "SwiftProjectLint" : labels.repo
        let repository = home.appendingPathComponent("xcode_projects").appendingPathComponent(folder)
        guard GitReader.output(["cat-file", "-e", labels.commit], in: repository) != nil else {
            return
        }
        let exported = try RevisionExport.export(
            commit: labels.commit,
            packagePath: labels.packagePath,
            from: repository
        )
        defer { try? FileManager.default.removeItem(at: RevisionExport.workDirectory(of: exported)) }
        let directory = try SnapshotHarness.temporaryDirectory("Labels")
        defer { try? FileManager.default.removeItem(at: directory) }
        let store = try SnapshotStore(at: directory.appendingPathComponent("stats.sqlite"))
        let scanner = SnapshotScanner(scanner: PackageScanner(tools: .nowhere), build: SnapshotHarness.build)
        let snapshot = try scanner.scan(
            packageAt: exported,
            configurationFile: StoreLocation.localConfiguration(packageRoot: exported),
            git: GitState(
                commit: labels.commit,
                branch: nil,
                isDirty: false,
                dirtyHash: nil,
                packagePath: labels.packagePath
            ),
            toolchain: SnapshotHarness.toolchain,
            history: .commit(top: repository, commit: labels.commit, packagePath: labels.packagePath)
        )
        let stored = try store.load(id: try store.save(snapshot))
        let signals = SignalEngine.signals(of: stored, thresholds: SignalThresholds())
        let hotspot = try #require(signals.first { $0.name == .hotspot })
        let current = hotspot.items.prefix(Self.labelledHotspots).map { "\($0.family)\u{0}\($0.file)" }
        let worth = Set(labels.items.filter { $0.label == "worth" }.map { "\($0.family)\u{0}\($0.file)" })

        let labelled = Set(labels.items.map { "\($0.family)\u{0}\($0.file)" })
        let entered = current.filter { labelled.contains($0) == false }
        #expect(entered.isEmpty, "unlabelled items entered the top 20: \(entered)")
        if labels.items.allSatisfy({ $0.label != nil }) {
            #expect(current.filter(worth.contains).count >= Self.worthNeeded)
        }
    }
}
