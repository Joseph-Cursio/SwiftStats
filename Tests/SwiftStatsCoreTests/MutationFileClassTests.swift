import Foundation
@testable import SwiftStatsCore
import Testing

/// The files mutants are in (M6, design §3), first match winning: build
/// products, files outside the root, test files, other languages' and
/// other packages' files are dropped with their class; production files
/// the scan didn't parse are unmapped (`excluded`, `not parsed`); in a
/// kept file the hash gate unmaps a mutant that tested other bytes
/// (`file changed`), a symbolic link (`symlink`) or a mutant with no hash.
/// Paths compare in NFC, a leading `./` doesn't count, and kept files whose
/// paths differ only in case are warned about.
@Suite("Mutation file classes")
struct MutationFileClassTests {
    /// The library's one function.
    private static let source = "public func one() -> Int {\n    1\n}\n"
    /// A library file named with a decomposed `é` (`e` and a combining
    /// acute accent).
    private static let decomposed = "Sources/Lib/Cafe\u{301}.swift"
    /// The same name precomposed, as NFC spells it.
    private static let precomposed = "Sources/Lib/Caf\u{E9}.swift"

    /// A library `Lib` with `Lib.swift`, an excluded file, a file that
    /// isn't UTF-8 and the decomposed file, and a test target, measured.
    private static func harness() throws -> MappingHarness {
        let package = try TemporaryPackage([
            "Sources/Lib/Lib.swift": source,
            "Sources/Lib/Excluded.swift": source,
            "Sources/Lib/Latin1.swift": "",
            decomposed: "public func cafe() -> Int {\n    2\n}\n",
            "Tests/LibTests/LibTests.swift": "",
            ".swiftstats.yml": "excluded:\n  - Sources/Lib/Excluded.swift\n"
        ])
        do {
            let latin1 = Data([0x6C, 0x65, 0x74, 0x20, 0x63, 0x61, 0x66, 0xE9, 0x20, 0x3D, 0x20, 0x31, 0x0A])
            try latin1.write(to: package.root.appendingPathComponent("Sources/Lib/Latin1.swift"))
            return try MappingHarness(package)
        } catch {
            package.remove()
            throw error
        }
    }

    /// Where a mutant at `path` (line 2, column 5) goes, its file hash
    /// `hash`.
    private static func place(_ path: String, hash: String?, in harness: MappingHarness) -> MutationMapper.Placed {
        let key = MutantKey(path: path, operatorID: "ReplaceReturnValue", line: 2, column: 5, occurrence: 0)
        return harness.place(MappingHarness.mutant(key, after: "0", fileSHA256: hash))
    }

    /// A mutant `place`d nowhere, for `reason`.
    private static func nowhere(_ place: MutationPlace, _ reason: String) -> MutationMapper.Placed {
        MutationMapper.Placed(place: place, owner: nil, reason: reason, anchor: nil)
    }

    @Test("""
        build products at any depth, files outside the root, test files, files that aren't Swift and files in no \
        target's directory are dropped, each with its class
        """)
    func dropped() throws {
        let harness = try Self.harness()
        defer { harness.remove() }
        let hash = try harness.hash("Sources/Lib/Lib.swift")

        let places = [
            ".build/checkouts/Dep/Sources/Dep/Dep.swift", "Sources/Lib/.build/Plugin.swift", "../Other/Other.swift",
            "/elsewhere/Other.swift", "Tests/LibTests/LibTests.swift", "Sources/Lib/shim.c", "Tools/Generate.swift"
        ].map { Self.place($0, hash: hash, in: harness) }

        #expect(places == [
            Self.nowhere(.dropped, "build"), Self.nowhere(.dropped, "build"), Self.nowhere(.dropped, "outsideRoot"),
            Self.nowhere(.dropped, "outsideRoot"), Self.nowhere(.dropped, "testFiles"),
            Self.nowhere(.dropped, "otherLanguage"), Self.nowhere(.dropped, "otherPackage")
        ])
    }

    @Test("""
        a production file the scan didn't parse is unmapped, `excluded` when the configuration excludes it and \
        `not parsed` when it isn't UTF-8
        """)
    func unparsed() throws {
        let harness = try Self.harness()
        defer { harness.remove() }

        let excludedHash = try harness.hash("Sources/Lib/Excluded.swift")
        let latin1Hash = try harness.hash("Sources/Lib/Latin1.swift")

        let excluded = Self.place("Sources/Lib/Excluded.swift", hash: excludedHash, in: harness)
        let latin1 = Self.place("Sources/Lib/Latin1.swift", hash: latin1Hash, in: harness)

        #expect(harness.measured.files.map(\.path).contains("Sources/Lib/Latin1.swift") == false)
        #expect(excluded == Self.nowhere(.unmapped, "excluded"))
        #expect(latin1 == Self.nowhere(.unmapped, "not parsed"))
    }

    @Test("""
        in a kept file, a mutant whose file hash isn't the scanned bytes' is unmapped as `file changed`, one with a \
        symbolic link's `link:` hash as `symlink`, and one with no hash as `no file hash`; with the scanned hash it \
        is placed
        """)
    func hashGate() throws {
        let harness = try Self.harness()
        defer { harness.remove() }
        let path = "Sources/Lib/Lib.swift"
        let scanned = try harness.hash(path)

        let changed = Self.place(path, hash: ContentHash.sha256(Data("other bytes".utf8)), in: harness)
        let linked = Self.place(path, hash: MutationTree.linkPrefix + scanned, in: harness)
        let unhashed = Self.place(path, hash: nil, in: harness)
        let placed = Self.place(path, hash: scanned, in: harness)

        #expect(changed == Self.nowhere(.unmapped, "file changed"))
        #expect(linked == Self.nowhere(.unmapped, "symlink"))
        #expect(unhashed == Self.nowhere(.unmapped, "no file hash"))
        #expect(placed == MutationMapper.Placed(
            place: .record,
            owner: "Lib::func one() -> Int",
            reason: nil,
            anchor: SourcePosition(line: 2, column: 5)
        ))
    }

    @Test("""
        a path spelled with a leading ./ or in another Unicode normalisation than the scan's names the same kept \
        file, which the mutant is placed in
        """)
    func spellings() throws {
        let harness = try Self.harness()
        defer { harness.remove() }

        let dotted = Self.place("./Sources/Lib/Lib.swift", hash: try harness.hash("Sources/Lib/Lib.swift"), in: harness)
        let composed = Self.place(Self.precomposed, hash: try harness.hash(Self.decomposed), in: harness)

        #expect(MutationMapper.normalized(Self.decomposed) == Self.precomposed)
        #expect(dotted.place == .record && dotted.owner == "Lib::func one() -> Int")
        #expect(composed.place == .record && composed.owner == "Lib::func cafe() -> Int")
    }

    @Test("kept files whose paths differ only in case get a warning; a package without such files gets none")
    func caseFolded() throws {
        let package = try TemporaryPackage([
            "Sources/Lib/Name.swift": Self.source,
            "Sources/Lib/name.swift": Self.source,
            "Tests/LibTests/NameTests.swift": "",
            "Tests/LibTests/nameTests.swift": ""
        ])
        let harness = try MappingHarness(package)
        defer { harness.remove() }
        let plain = try Self.harness()
        defer { plain.remove() }

        #expect(harness.mapper.warnings == [
            ScanWarning(
                file: nil,
                message: "swiftmutator: Sources/Lib/Name.swift, Sources/Lib/name.swift differ only in case, which a "
                    + "case-insensitive volume can't tell apart, so their mutants may be mapped to the wrong one"
            )
        ])
        #expect(plain.mapper.warnings.isEmpty)
    }

    @Test("""
        a report counts dropped mutants by class and unmapped ones by reason, and every mutant over both, keeping \
        each with its reason
        """)
    func reportCounts() throws {
        let harness = try Self.harness()
        defer { harness.remove() }
        let hash = try harness.hash("Sources/Lib/Lib.swift")
        let mutant = { (path: String, line: Int, outcome: String) in
            ResultsLines.mutant(
                ResultsLines.Mutant(path: path, line: line, column: 5, outcome: outcome, fileSHA256: hash)
            )
        }
        let results = try ResultsLines.results([
            ResultsLines.header(ResultsLines.Header(discovered: 5, tree: ["Sources/Lib/Lib.swift": hash])),
            mutant("Sources/Lib/Lib.swift", 2, "failed"),
            mutant("Sources/Lib/Lib.swift", 1, "passed"),
            mutant("Tests/LibTests/LibTests.swift", 2, "failed"),
            mutant("Sources/Lib/Excluded.swift", 2, "failed"),
            ResultsLines.mutant(
                ResultsLines.Mutant(path: "Sources/Lib/Lib.swift", line: 3, column: 1, fileSHA256: "0")
            ),
            ResultsLines.end(ResultsLines.End())
        ])

        let report = harness.report(results)

        #expect(report.dropped == MutationDropped(
            build: 0,
            outsideRoot: 0,
            testFiles: 1,
            otherLanguage: 0,
            otherPackage: 0
        ))
        #expect(report.unmapped == ["excluded": 1, "file changed": 1])
        #expect(report.everyMutant.dropped == 1 && report.everyMutant.unmapped == 2)
        #expect(report.everyMutant.counts.killed == 4 && report.everyMutant.counts.survived == 1)
        #expect(report.records.map(\.key) == ["Lib::func one() -> Int"])
        #expect(report.records.first?.counts.killed == 1 && report.records.first?.counts.survived == 1)
        #expect(report.mutants.filter { $0.place == .dropped }.map(\.reason) == ["testFiles"])
        #expect(report.files.map(\.disposition) == [.tested])
    }
}
