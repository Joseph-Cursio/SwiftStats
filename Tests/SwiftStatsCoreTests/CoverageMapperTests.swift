import Foundation
@testable import SwiftStatsCore
import Testing

/// The coverage mapping's edge cases (M5), on hand-written exports of a
/// small package: entries it can't place, saturated counts, files in every
/// class, and the scan's warning when names can't be demangled.
@Suite("Coverage mapper")
struct CoverageMapperTests {
    /// A small package's measurements, its targets and its real root path.
    private struct Measured {
        /// The package.
        let package: TemporaryPackage
        /// Its measurements.
        let measured: ScanMeasurements
        /// Its targets.
        let targets: [TargetSummary]
        /// Its root as `realpath(3)` gives it, as the export writes it.
        let realRoot: String
    }

    /// The library file the hand-written exports cover.
    private static let source = """
        public func first() -> Int {
            1
        }
        public struct Holder {
            public var value = 0
        }

        """

    /// A library whose subscript has no accessors, only a local function
    /// in its implicit getter.
    private static let gridSource = """
        public struct Grid {
            public subscript(index: Int) -> Int {
                func clamp(_ value: Int) -> Int { max(0, value) }
                return clamp(index)
            }
        }

        """

    /// The real path of `url`.
    private static func realPath(_ url: URL) -> String {
        guard let resolved = realpath(url.path, nil) else {
            return url.path
        }
        defer { free(resolved) }
        return String(cString: resolved)
    }

    /// The library holding `text`, measured.
    private static func measured(_ text: String = source) throws -> Measured {
        let package = try TemporaryPackage(["Sources/Lib/Lib.swift": text, "Tests/LibTests/LibTests.swift": ""])
        let targets = TargetResolver.resolve(try package.describer.describePackage(at: package.root))
        return Measured(
            package: package,
            measured: PackageScanner.measure(targets, root: package.root, configuration: SwiftStatsConfiguration()),
            targets: targets,
            realRoot: realPath(package.root)
        )
    }

    /// An export of `files` and `functions`, with `@ROOT@` the real root.
    private static func export(files: String, functions: String, root: String) throws -> CoverageExport {
        let text = #"{"data":[{"files":[\#(files)],"functions":[\#(functions)]}],"#
            + #""type":"llvm.coverage.json.export","version":"3.0.1"}"#
        return try CoverageExport.decode(Data(text.replacingOccurrences(of: "@ROOT@", with: root).utf8))
    }

    /// The profiles of a passing run of `LibTests` whose processes ran `counts`.
    private static func profiles(_ counts: [String: Int64]) -> CoverageProfiles {
        CoverageProfiles(
            export: URL(fileURLWithPath: "/dev/null"),
            bundles: ["LibTests"],
            testStatus: 0,
            hasExtraProfiles: false,
            counts: ["LibTests": counts]
        )
    }

    /// The mapping of an export of `files` and `functions` onto the small
    /// library holding `text`, with no test process's counts.
    static func mapping(files: String, functions: String, text: String) throws -> CoverageReport {
        try report(files: files, functions: functions, counts: [:], text: text)
    }

    /// The mapping of an export of `files` and `functions` onto the small
    /// library holding `text`, with `counts` its test target's.
    private static func report(
        files: String,
        functions: String,
        counts: [String: Int64],
        text: String = source
    ) throws -> CoverageReport {
        let small = try measured(text)
        defer { small.package.remove() }
        let mapper = CoverageMapper(
            measured: small.measured,
            targets: small.targets,
            root: small.package.root,
            excluded: []
        )
        return mapper.report(
            of: try export(files: files, functions: functions, root: small.realRoot),
            profiles: profiles(counts)
        ) { names in
            Dictionary(uniqueKeysWithValues: names.map { ($0, "demangled \($0)") })
        }
    }

    @Test("""
        an entry spanning two files or holding an expansion region, one with no code region and one whose \
        first region ends past its record are listed as unmapped, each with its reason and demangled name
        """)
    func unmappedReasons() throws {
        let lib = #""@ROOT@/Sources/Lib/Lib.swift""#
        let functions = """
            {"name":"$sTwoFiles","count":1,"filenames":[\(lib),"@ROOT@/Sources/Lib/Other.swift"],
             "regions":[[1,28,3,2,1,0,0,0]]},
            {"name":"$sExpansion","count":2,"filenames":[\(lib)],"regions":[[1,28,3,2,2,0,0,0],[2,5,2,6,2,0,1,1]]},
            {"name":"$sSkippedOnly","count":0,"filenames":[\(lib)],"regions":[[2,5,2,6,0,0,0,2]]},
            {"name":"$sPastRecord","count":3,"filenames":[\(lib)],"regions":[[1,28,4,3,3,0,0,0]]}
            """

        let report = try Self.report(files: #"{"filename":\#(lib),"segments":[]}"#, functions: functions, counts: [:])

        #expect(report.unmapped.map(\.name) == ["$sExpansion", "$sPastRecord", "$sTwoFiles", "$sSkippedOnly"])
        #expect(report.unmapped.map(\.reason) == [
            "macro or expansion region", "region extends past its record", "macro or expansion region",
            "no code region"
        ])
        #expect(report.unmapped.map(\.demangled) == report.unmapped.map { "demangled \($0.name)" })
        #expect(report.unmapped.first?.count == 2)
        #expect(report.records.first { $0.key == "Lib::func first() -> Int" }?.reason == "no coverage data")
    }

    @Test("a saturated count reads as covered and is listed by file and line; a count is never summed")
    func saturation() throws {
        let lib = #""@ROOT@/Sources/Lib/Lib.swift""#
        let files = """
            {"filename":\(lib),"segments":[[1,28,18446744073709551615,true,true,false],[3,2,0,false,false,false],
             [5,24,1,true,true,false],[5,25,0,false,false,false]]}
            """
        let functions = """
            {"name":"$s3Lib5firstSiyF","count":9223372036854775807,"filenames":[\(lib)],
             "regions":[[1,28,3,2,9223372036854775807,0,0,0]]},
            {"name":"$s3Lib5firstSiyFSiycfU_","count":9223372036854775807,"filenames":[\(lib)],
             "regions":[[1,28,3,2,9223372036854775807,0,0,0]]},
            {"name":"$s3Lib6HolderV5valueSivpfi","count":1,"filenames":[\(lib)],"regions":[[5,24,5,25,1,0,0,0]]}
            """

        let report = try Self.report(files: files, functions: functions, counts: ["$s3Lib5firstSiyF": Int64.max])

        let first = report.records.first { $0.key == "Lib::func first() -> Int" }
        // The closure's entry shares `first`'s range: both map to it, and
        // the range counts once, at the larger count, not their sum.
        #expect(report.unmapped.isEmpty)
        #expect(first?.lines == CoverageTally(covered: 3, total: 3))
        #expect(first?.regions == CoverageTally(covered: 1, total: 1))
        #expect(first?.testTargets == ["LibTests"])
        #expect(report.saturated == [CoverageSaturation(file: "Sources/Lib/Lib.swift", line: 1)])
        let saturatedRun = CoverageLineRun(start: 1, end: 3, count: Int64.max, partlyRun: false)
        #expect(report.files.first?.lines.first == saturatedRun)
        #expect(report.attachments == [
            CoverageAttachment(
                owner: "Lib::Holder",
                attachedTo: .type,
                lines: CoverageTally(covered: 1, total: 1),
                regions: CoverageTally(covered: 1, total: 1)
            )
        ])
    }

    @Test("""
        a subscript whose only child record is a local function is no container: with no entries it keeps \
        its reason, linked or not
        """)
    func subscriptWithoutAccessors() throws {
        let lib = #""@ROOT@/Sources/Lib/Lib.swift""#
        let subscriptKey = "Lib::Grid::subscript(_: Int) -> Int"

        let linked = try Self.report(
            files: #"{"filename":\#(lib),"segments":[]}"#,
            functions: "",
            counts: [:],
            text: Self.gridSource
        )
        let unlinked = try Self.report(files: "", functions: "", counts: [:], text: Self.gridSource)

        #expect(linked.records.map(\.key) == [subscriptKey, subscriptKey + " / func clamp(_: Int) -> Int"])
        #expect(linked.records.first { $0.key == subscriptKey }?.reason == "no coverage data")
        #expect(unlinked.records.first { $0.key == subscriptKey }?.reason == "not linked into any test bundle")
    }

    @Test("""
        export files sort by the root in any spelling: build products, outside the root, test files, kept, \
        excluded or unparsed production files, other packages, and files that aren't Swift, such as a C target's
        """)
    func fileClasses() throws {
        let base = FileManager.default.temporaryDirectory
            .appendingPathComponent("CoverageClasses-\(UUID().uuidString)")
        let real = base.appendingPathComponent("real")
        let link = base.appendingPathComponent("link")
        try FileManager.default.createDirectory(at: real, withIntermediateDirectories: true)
        try FileManager.default.createSymbolicLink(at: link, withDestinationURL: real)
        defer { try? FileManager.default.removeItem(at: base) }
        let targets = [
            TargetSummary(
                name: "Lib",
                type: "library",
                isTest: false,
                path: "Sources/Lib",
                files: ["Sources/Lib/Lib.swift"]
            ),
            TargetSummary(name: "LibTests", type: "test", isTest: true, path: "Tests/LibTests", files: [])
        ]
        let path = Self.realPath(real)
        let files = [
            "/.swiftstats/coverage-build/checkouts/X/Sources/X/A.swift",
            "/.swiftstats/coverage-build/out/Intermediates.noindex/T.build/DerivedSources/test_entry_point.swift",
            "/.build/checkouts/Y/B.swift",
            "/Tests/LibTests/T.swift",
            "/Sources/Lib/Lib.swift",
            "/Sources/Lib/Gone.swift",
            "/Sources/Lib/Odd.swift",
            "/Packages/Dep/Sources/Dep/D.swift",
            "/Sources/LibExtra/E.swift",
            "/Sources/CFoo/cfoo.c",
            "/Sources/CFoo/include/cfoo.h",
            "/Sources/Lib/shim.c",
            "/Tests/LibTests/helper.c"
        ].map { path + $0 } + ["/elsewhere/C.swift"]

        for root in [link, real] {
            let classifier = CoverageFileClassifier(
                root: root,
                build: ".swiftstats/coverage-build",
                targets: targets,
                parsed: ["Sources/Lib/Lib.swift"],
                excluded: [GlobPattern("Sources/Lib/Gone.swift")]
            )

            #expect(files.map(classifier.classify) == [
                .build, .build, .build, .testFile,
                .kept(path: "Sources/Lib/Lib.swift", module: "Lib"),
                .unmapped(path: "Sources/Lib/Gone.swift", module: "Lib", reason: "excluded"),
                .unmapped(path: "Sources/Lib/Odd.swift", module: "Lib", reason: "not parsed"),
                .otherPackage, .otherPackage, .otherLanguage, .otherLanguage, .otherLanguage, .testFile, .outsideRoot
            ], "root \(root.path)")
        }
    }

    @Test("when the toolchain can't demangle, the unmapped entries keep only their names and the scan warns")
    func demangleFailure() throws {
        let small = try Self.measured()
        defer { small.package.remove() }
        let export = try Self.export(
            files: "",
            functions: #"{"name":"$s3Lib3oddyyF","count":0,"filenames":["@ROOT@/Sources/Lib/Odd.swift"],"#
                + #""regions":[[1,1,1,2,0,0,0,0]]}"#,
            root: small.realRoot
        )
        let run = CoverageRun(
            status: CollectorStatus(name: CoverageAdapter.name, state: .ran, version: nil, reason: nil, options: []),
            executable: URL(fileURLWithPath: "/usr/bin/false"),
            identity: nil,
            milliseconds: 0,
            profiles: Self.profiles([:]),
            export: export
        )

        let mapped = PackageScanner.coverage(
            of: run,
            measured: small.measured,
            targets: small.targets,
            configuration: SwiftStatsConfiguration(),
            root: small.package.root
        )

        #expect(mapped.report?.unmapped.map(\.reason) == ["not parsed"])
        #expect(mapped.report?.unmapped.first?.demangled == nil)
        #expect(mapped.warnings.map(\.message) == [
            "coverage: `swift demangle` failed, so unmapped entries are listed without demangled names"
        ])
    }
}
