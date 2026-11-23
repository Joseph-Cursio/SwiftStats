import Foundation
@testable import SwiftStatsCore
import Testing

/// The recorded runs still describe the fixtures (M6, design §11): every
/// tree and mutant hash a recording holds equals the bytes of the file it
/// names, in the fixture or, for the since run, in its patched commit, so
/// a fixture edit can't silently turn mapped mutants into `file changed`;
/// and the repository the tests build has the commits the recordings name.
@Suite("Mutation fixture recordings")
struct MutationFixtureTests {
    /// Each regular file under `root` by its relative path, with its
    /// SHA-256, leaving out `.git` and what the repositories leave out.
    private static func hashes(under root: URL) -> [String: String] {
        let skipped = MutationFixture.leftOut.union(MutationFixture.leftOutAtTop).union([".git"])
        var hashes: [String: String] = [:]
        guard let enumerator = FileManager.default.enumerator(atPath: root.path) else {
            return hashes
        }
        while let relative = enumerator.nextObject() as? String {
            if skipped.contains(URL(fileURLWithPath: relative).lastPathComponent) {
                enumerator.skipDescendants()
                continue
            }
            if enumerator.fileAttributes?[.type] as? FileAttributeType == .typeRegular {
                hashes[relative] = ContentHash.sha256(ofFileAt: root.appendingPathComponent(relative))
            }
        }
        return hashes
    }

    /// The fixture's files with their hashes, plus the repository's
    /// `.gitignore`: the tree a recording of its `main` lists.
    private static func expectedTree(_ fixture: URL) -> [String: String] {
        hashes(under: fixture).merging([".gitignore": ContentHash.sha256(Data(MutationFixture.gitignore.utf8))]) { $1 }
    }

    /// Checks that `results`' tree is `tree` and every mutant's hash is its
    /// file's there.
    private static func check(_ results: MutationResults, against tree: [String: String]) {
        #expect(results.tree == tree)
        for mutant in results.mutants {
            #expect(mutant.fileSHA256 == tree[mutant.key.path], "\(mutant.key)")
        }
    }

    @Test(
        "every hash a recording of main holds is the fixture's file's",
        arguments: [
            (MutationFixture.coverageDirectory, "full"), (MutationFixture.directory, "full"),
            (MutationFixture.directory, "interrupted"), (MutationFixture.directory, "resumed")
        ]
    )
    func mainRecordings(_ fixture: URL, _ name: String) throws {
        let results = try MutationFixture.results(of: name, in: fixture)

        Self.check(results, against: Self.expectedTree(fixture))
        #expect(results.mutants.allSatisfy { $0.fileSHA256 != nil })
    }

    @Test("the tests' repository has the commits the recordings name, and the since run's tree is its branch's")
    func repository() throws {
        let repository = try MutationFixture.repository(of: MutationFixture.directory)
        defer { repository.remove() }
        let since = try MutationFixture.results(of: "since", in: MutationFixture.directory)

        #expect(repository.commits == (try MutationFixture.recordedCommits(in: MutationFixture.directory)))
        #expect(repository.commits.keys.sorted() == ["main", "since", "since-unlisted", "stopped", "tests-only"])
        #expect(since.facts.since?.commit == repository.commits["main"])
        try repository.checkOut("since")
        Self.check(since, against: Self.hashes(under: repository.root))
        let checkedOut = Self.hashes(under: repository.root)
        #expect(since.facts.since?.files.allSatisfy { checkedOut[$0.path] == $0.sha256 } == true)
    }

    @Test("the Coverage fixture's repository has the commit its recording names")
    func coverageRepository() throws {
        let repository = try MutationFixture.repository(of: MutationFixture.coverageDirectory)
        defer { repository.remove() }

        #expect(repository.commits == (try MutationFixture.recordedCommits(in: MutationFixture.coverageDirectory)))
        #expect(Self.hashes(under: repository.root) == Self.expectedTree(MutationFixture.coverageDirectory))
    }
}
