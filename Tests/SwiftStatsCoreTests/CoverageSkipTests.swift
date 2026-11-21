import Foundation
import SwiftParser
@testable import SwiftStatsCore
import SwiftSyntax
import Testing

/// The coverage run's `--skip` regexes, from `collectors.coverage.arguments`
/// to the tests per public function a scan counts (M5), and what Swift
/// Testing matches them against.
@Suite("Coverage skips")
struct CoverageSkipTests {
    /// A library function every test calls, its body's braces on lines 1 to 3.
    private static let library = """
        public func compute() -> Int {
            1
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

    /// The tests a scan links to `compute()` when the configuration's
    /// coverage arguments are `arguments`, from an export whose one entry
    /// `LibTests` ran.
    private static func linkedTests(arguments: [String]) throws -> Int? {
        let package = try TemporaryPackage([
            "Sources/Lib/Lib.swift": library,
            "Tests/LibTests/LibTests.swift": """
                import Testing

                @Test func fast() { #expect(compute() == 1) }
                @Test func slowCompute() { #expect(compute() == 1) }

                """
        ])
        defer { package.remove() }
        let targets = TargetResolver.resolve(try package.describer.describePackage(at: package.root))
        let measured = PackageScanner.measure(targets, root: package.root, configuration: SwiftStatsConfiguration())
        let root = realPath(package.root)
        let text = #"{"data":[{"files":[{"filename":"\#(root)/Sources/Lib/Lib.swift","segments":[]}],"#
            + #""functions":[{"name":"compute","count":1,"filenames":["\#(root)/Sources/Lib/Lib.swift"],"#
            + #""regions":[[1,30,3,2,1,0,0,0]]}]}],"type":"llvm.coverage.json.export","version":"3.0.1"}"#
        let run = CoverageRun(
            status: CollectorStatus(name: CoverageAdapter.name, state: .ran, version: nil, reason: nil, options: []),
            executable: nil,
            identity: nil,
            milliseconds: 0,
            profiles: CoverageProfiles(
                export: URL(fileURLWithPath: "/dev/null"),
                bundles: ["LibTests"],
                testStatus: 0,
                hasExtraProfiles: false,
                counts: ["LibTests": ["compute": 1]]
            ),
            export: try CoverageExport.decode(Data(text.utf8))
        )
        let configuration = SwiftStatsConfiguration(
            excluded: [],
            generated: GeneratedCode.defaultGlobs,
            collectors: [CoverageAdapter.name: CollectorSettings(enabled: true, path: nil, arguments: arguments)],
            store: nil,
            history: .standard,
            signals: SignalThresholds(),
            unusedKeys: [],
            source: nil
        )
        let mapped = PackageScanner.coverage(
            of: run,
            measured: measured,
            targets: targets,
            configuration: configuration,
            root: package.root
        )
        return mapped.report?.records.first { $0.key == "Lib::func compute() -> Int" }?.linkedTests
    }

    @Test("the regexes of `collectors.coverage.arguments` are those after each `--skip`, in order")
    func patterns() {
        #expect(CoverageArguments.skipPatterns(in: ["--skip", "A", "--skip", "B|C"]) == ["A", "B|C"])
        #expect(CoverageArguments.skipPatterns(in: []).isEmpty)
    }

    @Test("a scan leaves out the tests its coverage arguments' `--skip` regexes match")
    func scanSkips() throws {
        #expect(try Self.linkedTests(arguments: []) == 2)
        #expect(try Self.linkedTests(arguments: ["--skip", "slow"]) == 1)
        #expect(try Self.linkedTests(arguments: ["--skip", "fast", "--skip", "slow"]) == 0)
    }

    @Test("""
        a Swift Testing test's location is its `@Test` attribute's name and its tags its own; a `@Suite` type is \
        found by its path, extensions included, with its tags, named as Swift Testing names them
        """)
    func identity() throws {
        let source = """
            @Suite(.tags(.slow)) struct Outer {
                struct Middle {}
            }
            extension Outer.Middle {
                @Suite(.tags(Tag.fast)) struct Inner {
                    @available(macOS 15, *)
                    @Test(.tags(.Speed.quick), .serialized) func check() {}
                }
            }
            """
        let tree = Parser.parse(source: source)
        let converter = SourceLocationConverter(fileName: "Check.swift", tree: tree)
        let finder = FunctionFinder(viewMode: .sourceAccurate)
        finder.walk(tree)
        let function = try #require(finder.found.first)

        let identity = try #require(SwiftTestingIdentity(function) { node in
            let location = converter.location(for: node.positionAfterSkippingLeadingTrivia)
            return (location.line, location.column)
        })

        #expect(identity.line == 7)
        #expect(identity.column == 10)
        #expect(identity.tags == ["Speed.quick"])
        #expect(finder.suites.map(\.path) == [["Outer"], ["Outer", "Middle", "Inner"]])
        #expect(finder.suites.map(\.tags) == [["slow"], ["fast"]])
    }
}
