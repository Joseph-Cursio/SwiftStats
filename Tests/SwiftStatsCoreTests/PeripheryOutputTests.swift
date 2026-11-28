import Foundation
@testable import SwiftStatsCore
import Testing

/// outskirts' JSON read and classed (M7, design §5.3): the nine keys each
/// required and typed, extra keys ignored, one hint split as
/// `name(text)`, locations read from the right on scalars (design B23),
/// modules made target names; then each entry's class, the first that
/// applies, on the Index fixture's recorded runs and on hand-written
/// entries placed in it. Hints read on scalars are in
/// `PeripheryOutputTests+Scalars`.
@Suite("outskirts output")
struct PeripheryOutputTests {
    /// One entry's JSON object, its fields as given.
    private static func entry(
        location: String,
        kind: String = "function.free",
        hints: [String] = ["unused"],
        ids: [String] = ["s:9IndexCore1fyyF"],
        modules: [String] = ["IndexCore"]
    ) -> [String: Any] {
        [
            "accessibility": "internal", "attributes": [String](), "hints": hints, "ids": ids, "kind": kind,
            "location": location, "modifiers": [String](), "modules": modules, "name": "f()"
        ]
    }

    /// `objects` as a run's JSON.
    static func json(_ objects: [Any]) throws -> Data {
        try JSONSerialization.data(withJSONObject: objects, options: [.sortedKeys])
    }

    /// A context for a package at `/NoSuchPeripheryPackage`, which doesn't
    /// exist, described as the recorded T1 describe gives the Index
    /// fixture, with no records.
    static func plainContext() throws -> PeripheryOutput.Context {
        let package = try IndexWalkHarness.recordedPackage()
        return PeripheryOutput.Context(
            root: "/NoSuchPeripheryPackage",
            scratch: "/NoSuchPeripheryPackage/.swiftstats/index-build",
            package: package,
            modules: try BuildSession.moduleMap(of: package),
            files: ["Sources/IndexCore/Locals.swift": "IndexCore"],
            changedFiles: [],
            records: [],
            localUSRs: []
        )
    }

    /// A context for `fixture`, its scanned files changed as `changed`
    /// says and `localUSRs` read as local by the index.
    private static func context(
        _ fixture: BuildFixture,
        changed: Set<String> = [],
        localUSRs: Set<String> = []
    ) throws -> PeripheryOutput.Context {
        let package = try IndexWalkHarness.recordedPackage()
        return PeripheryOutput.Context(
            root: fixture.root,
            scratch: fixture.build,
            package: package,
            modules: try BuildSession.moduleMap(of: package),
            files: Dictionary(fixture.measured.files.map { ($0.path, $0.module) }) { first, _ in first },
            changedFiles: changed,
            records: fixture.measured.records,
            localUSRs: localUSRs
        )
    }

    /// The format failure decoding `data` as the production run with
    /// `context` gives; nil when it decodes.
    private static func failure(_ data: Data, context: PeripheryOutput.Context) -> String? {
        do {
            _ = try PeripheryOutput.decode(data, run: .production, context: context)
            return nil
        } catch {
            return (error as? PeripheryOutput.FormatFailure)?.description ?? "\(error)"
        }
    }

    @Test("every one of the nine keys is required, naming the key, the entry and the run")
    func requiredKeys() throws {
        let context = try Self.plainContext()
        let good = Self.entry(location: "/NoSuchPeripheryPackage/Sources/IndexCore/Locals.swift:3:6")
        for key in PeripheryOutput.keys {
            var lacking = good
            lacking[key] = nil
            #expect(Self.failure(try Self.json([good, lacking]), context: context)
                == "JSON lacks \"\(key)\" in entry 2 of the production run")
        }
        #expect(Self.failure(try Self.json([good]), context: context) == nil)
    }

    @Test("""
        a value of another type, a hints list without exactly one hint, a location that isn't path:line:column, \
        an entry that isn't an object, output that isn't an array or isn't JSON are format failures
        """)
    func malformed() throws {
        let context = try Self.plainContext()
        let place = "in entry 1 of the production run"
        var number = Self.entry(location: "/NoSuchPeripheryPackage/a.swift:1:1")
        number["kind"] = 3
        #expect(Self.failure(try Self.json([number]), context: context) == "JSON's \"kind\" isn't a string \(place)")
        var mixed = Self.entry(location: "/NoSuchPeripheryPackage/a.swift:1:1")
        mixed["ids"] = ["s:x", 1] as [Any]
        #expect(Self.failure(try Self.json([mixed]), context: context)
            == "JSON's \"ids\" isn't a list of strings \(place)")
        let two = Self.entry(location: "/NoSuchPeripheryPackage/a.swift:1:1", hints: ["unused", "assignOnlyProperty"])
        #expect(Self.failure(try Self.json([two]), context: context)
            == "JSON's \"hints\" holds 2 hints, not one, \(place)")
        let none = Self.entry(location: "/NoSuchPeripheryPackage/a.swift:1:1", hints: [])
        #expect(Self.failure(try Self.json([none]), context: context)
            == "JSON's \"hints\" holds 0 hints, not one, \(place)")
        let file = "/NoSuchPeripheryPackage/a.swift"
        for location in [file + ":0:8", file + ":3", ":3:8", file + ":3:x", file + ":-3:8"] {
            #expect(Self.failure(try Self.json([Self.entry(location: location)]), context: context)
                == "JSON's \"location\" isn't path:line:column \(place)")
        }
        #expect(Self.failure(try Self.json(["text"]), context: context)
            == "JSON has an entry that isn't an object \(place)")
        #expect(Self.failure(Data("{}".utf8), context: context) == "JSON isn't an array in the production run")
        let text = Self.failure(Data("not json".utf8), context: context) ?? ""
        #expect(text.hasPrefix("JSON doesn't decode in the production run: "))
    }

    @Test(
        """
        a location whose path ends in a Prepend scalar, which joins the colon after it into one Character, reads \
        from the right on scalars, the scalar staying in the path (design B23, decided U13)
        """,
        arguments: ["\u{600}", "\u{6DD}"]
    )
    func prependBeforeLocationColon(prepend: String) throws {
        let path = "/NoSuchPeripheryPackage/Sources/a:b c.swift" + prepend
        #expect(PeripheryFields.Location(path + ":36:17") == PeripheryFields.Location(path: path, line: 36, column: 17))
        let entries = try PeripheryOutput.decode(
            try Self.json([Self.entry(location: path + ":36:17")]),
            run: .roots,
            context: try Self.plainContext()
        )
        let entry = try #require(entries.first)
        #expect(entry.path == path && entry.file == "Sources/a:b c.swift" + prepend)
        #expect(entry.line == 36 && entry.column == 17)
    }

    @Test("""
        an empty array reads as no entries; extra keys are ignored; a hint with parentheses keeps its text; \
        synthetic ids are kept; a path with colons and spaces reads whole; package modules become target names
        """)
    func decoding() throws {
        let context = try Self.plainContext()
        #expect(try PeripheryOutput.decode(Data("[]".utf8), run: .roots, context: context).isEmpty)
        var conformance = Self.entry(
            location: "/NoSuchPeripheryPackage/Sources/a:b c.swift:36:17",
            kind: "protocol",
            hints: ["redundantConformance(replace with: 'A, B')"],
            ids: ["s:9IndexCore1PP"],
            modules: ["index_kit", "IndexDepKit"]
        )
        conformance["asset"] = "extra"
        conformance["range"] = ["start": 1]
        let parameter = Self.entry(
            location: "/NoSuchPeripheryPackage/Sources/IndexCore/Locals.swift:25:25",
            kind: "var.parameter",
            ids: ["param-values-summarize(_:)-s:9IndexCore9summarizeySiSaySiGF"],
            modules: ["index_support"]
        )
        let data = try Self.json([conformance, parameter])
        let entries = try PeripheryOutput.decode(data, run: .roots, context: context)

        #expect(entries.count == 2)
        let first = try #require(entries.first)
        #expect(first.run == .roots && first.ordinal == 1)
        #expect(first.hint == "redundantConformance" && first.hintText == "replace with: 'A, B'")
        #expect(first.kind == "protocol" && first.name == "f()" && first.accessibility == "internal")
        #expect(first.path == "/NoSuchPeripheryPackage/Sources/a:b c.swift" && first.file == "Sources/a:b c.swift")
        #expect(first.line == 36 && first.column == 17)
        #expect(first.modules == ["index-kit", "IndexDepKit"])
        #expect(first.entryClass == .unscanned)
        let second = try #require(entries.last)
        #expect(second.ordinal == 2 && second.hint == "unused" && second.hintText == nil)
        #expect(second.ids == ["param-values-summarize(_:)-s:9IndexCore9summarizeySiSaySiGF"])
        #expect(second.modules == ["index-support"])
        #expect(second.entryClass == .production)
    }

    @Test("""
        the fixture's recorded production run: the unused local let is local by its place, IndexDep's let is \
        outside the root, the local function, the extension of Unused and the rest are production code
        """)
    func recordedClasses() throws {
        let fixture = try BuildFixture()
        defer { fixture.remove() }
        let data = try fixture.recorded("outskirts-production.json")

        let entries = try PeripheryOutput.decode(data, run: .production, context: try Self.context(fixture))

        #expect(entries.map(\.ordinal) == Array(1...10))
        let classes = entries.map { "\($0.name) \($0.entryClass.rawValue)" }
        #expect(classes == [
            "unusedComputed production", "unusedTotal local", "unusedHelper() production",
            "onlyTestsCall() production", "neverCalled() production", "Unused production", "Unused production",
            "relay() production", "parseLine(_:) production", "unusedInDependency outsideRoot"
        ])
        #expect(entries.map(\.file) == [
            "Sources/IndexCore/Accessors.swift", "Sources/IndexCore/Locals.swift", "Sources/IndexCore/Locals.swift",
            "Sources/IndexCore/TestOnly.swift", "Sources/IndexCore/TestOnly.swift",
            "Sources/IndexCore/Unused+Extra.swift", "Sources/IndexCore/Unused.swift", "Sources/Kits/Relay.swift",
            "Sources/Kits/Support.swift", nil
        ])
        #expect(entries[7].modules == ["index-kit"] && entries[8].modules == ["index-support"])
        #expect(entries[9].modules == ["IndexDepKit"])
        let roots = try PeripheryOutput.decode(
            try fixture.recorded("outskirts-roots.json"),
            run: .roots,
            context: try Self.context(fixture)
        )
        #expect(roots.count == 8 && roots.allSatisfy { $0.run == .roots })
    }

    @Test("""
        a top-level variable in main.swift stays production by its place but is local when the index marks its \
        USR local; a parameter is never local; the first class that applies wins
        """)
    func classOrder() throws {
        let fixture = try BuildFixture()
        defer { fixture.remove() }
        let root = fixture.root
        let core = root + "/Sources/IndexCore/"
        let data = try Self.json([
            Self.entry(
                location: root + "/Sources/IndexApp/main.swift:6:5",
                kind: "var.global",
                ids: ["s:8IndexApp8greetingSSvp"],
                modules: ["IndexApp"]
            ),
            Self.entry(location: core + "Locals.swift:25:25", kind: "var.parameter", ids: ["param-values"]),
            Self.entry(location: core + "Locals.swift:26:9", kind: "var.global", ids: ["s:local"]),
            Self.entry(location: root + "/Tests/IndexCoreTests/IndexCoreTests.swift:3:6", modules: ["IndexCoreTests"]),
            Self.entry(location: core + "TestOnly.swift:7:6", modules: ["IndexCoreTests", "IndexXCTests"]),
            Self.entry(location: root + "/Tests/IndexCoreTests/Unparsed.swift:1:6"),
            Self.entry(location: core + "Unparsed.swift:1:6", modules: ["IndexCoreTests"]),
            Self.entry(location: root + "/Package.swift:1:1"),
            Self.entry(location: fixture.build + "/checkouts/Dep/Dep.swift:2:3")
        ])

        let byPlace = try PeripheryOutput.decode(data, run: .roots, context: try Self.context(fixture))
        let byIndex = try PeripheryOutput.decode(
            data,
            run: .roots,
            context: try Self.context(fixture, localUSRs: ["s:8IndexApp8greetingSSvp"])
        )
        let changed = try PeripheryOutput.decode(
            data,
            run: .roots,
            context: try Self.context(
                fixture,
                changed: ["Sources/IndexCore/Locals.swift", "Tests/IndexCoreTests/IndexCoreTests.swift"]
            )
        )

        // TestOnly.swift is IndexCore's, so its modules don't make it test
        // code; only the unparsed files fall back to the folder or modules.
        #expect(byPlace.map(\.entryClass) == [
            .production, .production, .local, .test, .production, .test, .test, .unscanned, .build
        ])
        #expect(byIndex.map(\.entryClass) == [
            .local, .production, .local, .test, .production, .test, .test, .unscanned, .build
        ])
        #expect(changed.map(\.entryClass) == [
            .production, .fileChanged, .fileChanged, .test, .production, .test, .test, .unscanned, .build
        ])
        #expect(byPlace.last?.file == ".swiftstats/index-build/checkouts/Dep/Dep.swift")
    }

    @Test("the rule names the classes in the order they apply")
    func classes() {
        #expect(PeripheryOutput.rule.hasPrefix("""
            build, outside the root, test targets (the scanned file's target; an unscanned file's test directory \
            or modules), unscanned, files changed
            """))
    }
}
