import Foundation
@testable import SwiftStatsCore
import Testing

/// The `periphery` collector's runs of outskirts (M7, design §5.1–§5.3,
/// §5.5): the exact command lines, each flag its own argument, made in the
/// package root with standard input empty; the modules retained by C99
/// name and listed by target name; the empty configuration and both
/// outputs kept in the build directory; the stale units moved out when the
/// index didn't run; and every way a run fails or warns. A copy of the
/// Index fixture is scanned against its recorded build and dump, and a
/// fake outskirts acts out the recorded runs. Serialized, each scan on a
/// thread of its own, as the index collector's tests are.
@Suite("Periphery collector", .serialized)
struct PeripheryAdapterTests {
    /// The C99 names of the fixture's library-product targets, in byte
    /// order.
    private static let retained = ["IndexCore", "index_kit"]
    /// The stale case's units the quarantine moves.
    private static let staleUnits = ["Formatting.o-2O0IO76AFY1BN", "Relay.o-IUHAYC5KOBIV"]

    /// The arguments of `run` over the build directory `build` (a real
    /// path), retaining `retained`, as design §5.2 words them.
    static func arguments(_ run: PeripheryCommand.Run, build: String, retained: [String]) -> [String] {
        [
            "scan", "--format", "json", "--disable-update-check",
            "--config", build + "/swiftstats-outskirts.yml",
            "--index-store-path", build + "/out", "--skip-build",
            "--index-exclude", build + "/**",
            "--json-package-manifest-path", build + "/swiftstats-describe.json"
        ]
            + (retained.isEmpty ? [] : ["--retain-public-modules"] + retained)
            + ["--retain-codable-properties", "--retain-equatable-properties"]
            + (run == .production ? ["--exclude-tests"] : [])
    }

    /// The collector's options when it ran retaining `retained` (C99
    /// names), listed as `targets`.
    static func options(retained: [String], targets: String) -> [String] {
        let tail = retained.isEmpty ? "" : " --retain-public-modules " + retained.joined(separator: " ")
        let line = "outskirts scan --format json --disable-update-check --config <config> --index-store-path "
            + "<build>/out --skip-build --index-exclude <build>/** --json-package-manifest-path <describe>"
            + tail + " --retain-codable-properties --retain-equatable-properties"
        return [
            "roots: " + line,
            "production: " + line + " --exclude-tests",
            "retain-public-modules: " + targets + " " + PeripheryCommand.retainRule,
            "classes: " + PeripheryOutput.rule,
            "map: " + DeadCodeMapper.rule
        ]
    }

    /// The recorded T1 describe edited by `edit`, as the fake build prints
    /// it.
    private static func describe(editing edit: (inout [String: Any]) -> Void) throws -> String {
        let data = try IndexFixture.data("describe.json")
        guard var object = try JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            throw IndexFixtureScanError(description: "describe.json isn't an object")
        }
        edit(&object)
        let written = try JSONSerialization.data(withJSONObject: object, options: [.prettyPrinted, .sortedKeys])
        return String(bytes: written, encoding: .utf8) ?? ""
    }

    /// Scans the fixture with `scan`, outskirts acted out by a fake
    /// playing `scenario`, and passes the copy, what the scan gave and the
    /// fake to `check`.
    static func scanning(
        _ scenario: FakePeriphery.Scenario,
        with scan: IndexFixtureScan,
        check: (BuildFixture, IndexGroupHarness.Outcome, FakePeriphery) throws -> Void
    ) async throws {
        let fake = try FakePeriphery.make(scenario)
        defer { fake.remove() }
        var configured = scan
        configured.extra = fake.configuration + scan.extra
        try await configured.run { fixture, outcome in
            try check(fixture, outcome, fake)
        }
    }

    @Test("""
        on the fixture, outskirts is asked its version, then runs roots and production in the package root, \
        standard input empty, with design 5.2's arguments each its own, the real build directory and the \
        library-product modules by C99 name in byte order; both outputs and the empty configuration are kept
        """)
    func runs() async throws {
        try await Self.scanning(try FakePeriphery.recorded(), with: try IndexFixtureScan()) { fixture, outcome, fake in
            let build = fixture.paths.build
            #expect(fake.calls == ["version", "roots", "production"])
            for run in PeripheryCommand.Run.ordered {
                #expect(fake.arguments(of: run) == Self.arguments(run, build: build, retained: Self.retained))
                #expect(fake.directory(of: run) == fixture.paths.root)
                #expect(fake.input(of: run) == "null")
                let file = build + "/" + PeripheryCommand.outputName(run)
                let kept = try String(contentsOfFile: file, encoding: .utf8)
                let recorded = try IndexFixture.text("outskirts-\(run.rawValue).json")
                    .replacingOccurrences(of: IndexFixture.rootToken, with: fixture.paths.root)
                    .replacingOccurrences(of: IndexFixture.dependencyToken, with: fixture.paths.dependency)
                #expect(kept == recorded)
            }
            let configurationFile = build + "/swiftstats-outskirts.yml"
            let configuration = try FileManager.default.attributesOfItem(atPath: configurationFile)
            #expect(configuration[.size] as? Int == 0)
            #expect(outcome.statuses["periphery"] == CollectorStatus(
                name: "periphery",
                state: .ran,
                version: "3.28.0",
                reason: nil,
                options: Self.options(retained: Self.retained, targets: "IndexCore, index-kit")
            ))
            let run = try #require(outcome.run("periphery"))
            let hash = try #require(ContentHash.sha256(ofFileAt: fake.tool))
            #expect(run.identity == "sha256:" + hash)
            #expect(run.identityLabel == nil)
            #expect(outcome.report.warnings.allSatisfy { $0.message.hasPrefix("periphery") == false })
        }
    }

    @Test("""
        a package without library products leaves --retain-public-modules out and lists none; a binary target \
        in a library product, which has no units, isn't retained
        """)
    func retainedModules() async throws {
        var bare = try IndexFixtureScan()
        bare.scenario.describe = try Self.describe { object in
            let products = object["products"] as? [[String: Any]] ?? []
            object["products"] = products.filter { product in
                (product["type"] as? [String: Any])?["library"] == nil
            }
        }
        try await Self.scanning(try FakePeriphery.recorded(), with: bare) { fixture, outcome, fake in
            #expect(fake.arguments(of: .roots) == Self.arguments(.roots, build: fixture.paths.build, retained: []))
            #expect(outcome.statuses["periphery"]?.options == Self.options(retained: [], targets: "none"))
        }

        var binary = try IndexFixtureScan()
        binary.scenario.describe = try Self.describe { object in
            let targets = object["targets"] as? [[String: Any]] ?? []
            let binaryTarget: [String: Any] = [
                "name": "IndexBinary", "c99name": "IndexBinary", "type": "binary", "module_type": "BinaryTarget",
                "path": "Binaries/IndexBinary.xcframework", "sources": [String]()
            ]
            object["targets"] = targets + [binaryTarget]
            let products = object["products"] as? [[String: Any]] ?? []
            object["products"] = products.map { product in
                var edited = product
                if product["name"] as? String == "IndexCore" {
                    edited["targets"] = (product["targets"] as? [String] ?? []) + ["IndexBinary"]
                }
                return edited
            }
        }
        try await Self.scanning(try FakePeriphery.recorded(), with: binary) { fixture, outcome, fake in
            let build = fixture.paths.build
            let expected = Self.arguments(.production, build: build, retained: Self.retained)
            #expect(fake.arguments(of: .production) == expected)
            let options = outcome.statuses["periphery"]?.options ?? []
            #expect(options.contains(PeripheryCommand.retainOption(targets: ["IndexCore", "index-kit"])))
        }
    }

    @Test("""
        with the index disabled, the collector reads the unit headers itself, moves the stale case's two old \
        units out of the store before outskirts runs, and notes that results are mapped by position
        """)
    func quarantineWithoutIndex() async throws {
        var scan = try IndexFixtureScan()
        scan.dump = "reader-stale.json"
        scan.scenario.describe = try IndexFixtureScan.staleDescribe()
        scan.extra = "  index:\n    enabled: false\n"
        scan.prepare = { fixture in
            let root = fixture.package.root
            try FileManager.default.copyItem(
                at: root.appendingPathComponent(IndexFixture.staleRename.from),
                to: root.appendingPathComponent(IndexFixture.staleRename.to)
            )
            let units = URL(fileURLWithPath: fixture.paths.build).appendingPathComponent("out/v5/units")
            try FileManager.default.createDirectory(at: units, withIntermediateDirectories: true)
            for name in Self.staleUnits + ["Kit.o-3SHEV4SLQQ5MS"] {
                try Data().write(to: units.appendingPathComponent(name))
            }
        }
        try await Self.scanning(try FakePeriphery.recorded(), with: scan) { fixture, outcome, fake in
            #expect(outcome.statuses["index"]?.reason == "disabled by collectors.index.enabled")
            let periphery = try #require(outcome.statuses["periphery"])
            #expect(periphery.state == .ran)
            #expect(periphery.reason == PeripheryAdapter.positionNote)
            #expect(periphery.options.contains(PeripheryCommand.retainOption(targets: ["IndexCore", "index-kit"])))
            #expect(fake.calls == ["version", "roots", "production"])
            let build = URL(fileURLWithPath: fixture.paths.build)
            let moved = try FileManager.default.contentsOfDirectory(
                atPath: build.appendingPathComponent(UnitFilter.quarantineDirectory).path
            )
            #expect(moved.sorted() == Self.staleUnits)
            let units = build.appendingPathComponent("out/v5/units")
            let left = try FileManager.default.contentsOfDirectory(atPath: units.path)
            #expect(left == ["Kit.o-3SHEV4SLQQ5MS"])
        }
    }

    @Test("""
        a run exiting 1 or 64 fails the collector with its last standard-error lines, outskirts' routine \
        warning dropped and paths redacted, and the production run isn't made; a production run that fails \
        after roots succeeded fails it too
        """)
    func failingRuns() async throws {
        var exit1 = try FakePeriphery.recorded()
        exit1.errors[.roots] = FakePeriphery.xcodeWarning + "\nerror: the index store at @ROOT@/x is damaged\n"
        exit1.statuses[.roots] = 1
        try await Self.scanning(exit1, with: try IndexFixtureScan()) { fixture, outcome, fake in
            let periphery = try #require(outcome.statuses["periphery"])
            #expect(periphery.state == .failed)
            #expect(periphery.reason
                == "outskirts scan (roots) exited 1: error: the index store at <package>/x is damaged")
            #expect(periphery.options == Self.options(retained: Self.retained, targets: "IndexCore, index-kit"))
            #expect(fake.calls == ["version", "roots"])
            #expect(outcome.run("periphery")?.identity?.hasPrefix("sha256:") == true)
            #expect(periphery.reason?.contains(fixture.paths.root) == false)
        }

        var usage = try FakePeriphery.recorded()
        usage.errors[.roots] = "Error: Unknown option '--x'\nUsage: outskirts scan [<options>]\n"
        usage.statuses[.roots] = 64
        try await Self.scanning(usage, with: try IndexFixtureScan()) { _, outcome, _ in
            #expect(outcome.statuses["periphery"]?.reason
                == "outskirts scan (roots) exited 64: Error: Unknown option '--x'\nUsage: outskirts scan [<options>]")
        }

        var production = try FakePeriphery.recorded()
        production.errors[.production] = "Error: boom\n"
        production.statuses[.production] = 1
        try await Self.scanning(production, with: try IndexFixtureScan()) { _, outcome, fake in
            #expect(outcome.statuses["periphery"]?.state == .failed)
            #expect(outcome.statuses["periphery"]?.reason == "outskirts scan (production) exited 1: Error: boom")
            #expect(fake.calls == ["version", "roots", "production"])
        }
    }

    @Test("""
        a warning that a retained module wasn't scanned fails the collector, naming the module by target name; \
        an entry lacking a key fails it naming outskirts' version, its hash and the entry; a failing version \
        command fails it before any run
        """)
    func refusedOutputs() async throws {
        var unscanned = try FakePeriphery.recorded()
        unscanned.errors[.roots] = "warning: retain_public_modules lists modules that are not scanned, whose public "
            + "declarations are therefore not retained: index_kit\n"
        try await Self.scanning(unscanned, with: try IndexFixtureScan()) { _, outcome, fake in
            #expect(outcome.statuses["periphery"]?.state == .failed)
            #expect(outcome.statuses["periphery"]?.reason == "outskirts didn't scan retained module(s) index-kit")
            #expect(fake.calls == ["version", "roots"])
        }

        var missing = try FakePeriphery.recorded()
        missing.outputs[.roots] = """
            [{"accessibility": "internal", "attributes": [], "hints": ["unused"], "ids": ["s:x"], "kind": "struct",
              "location": "@ROOT@/Sources/IndexCore/Unused.swift:3:8", "modifiers": [], "name": "Unused"}]
            """
        try await Self.scanning(missing, with: try IndexFixtureScan()) { _, outcome, fake in
            let hash = try #require(ContentHash.sha256(ofFileAt: fake.tool))
            #expect(outcome.statuses["periphery"]?.reason
                == "outskirts 3.28.0 (sha256:\(hash.prefix(10))) JSON lacks \"modules\" in entry 1 of the roots run")
            #expect(fake.calls == ["version", "roots"])
        }

        var version = try FakePeriphery.recorded()
        version.version = "error: unable to start"
        version.versionStatus = 1
        try await Self.scanning(version, with: try IndexFixtureScan()) { _, outcome, fake in
            #expect(outcome.statuses["periphery"]?.state == .failed)
            #expect(outcome.statuses["periphery"]?.reason == "outskirts version exited 1: error: unable to start")
            #expect(outcome.statuses["periphery"]?.options.isEmpty == true)
            #expect(fake.calls == ["version"])
        }
    }

    @Test("""
        another outskirts version runs, noting in its reason and warning that it isn't the version SwiftStats \
        was checked against
        """)
    func otherVersion() async throws {
        var scenario = try FakePeriphery.recorded()
        scenario.version = "3.29.0"
        try await Self.scanning(scenario, with: try IndexFixtureScan()) { _, outcome, _ in
            let note = "outskirts 3.29.0 isn't the version SwiftStats was checked against (3.28.0); results may differ"
            #expect(outcome.statuses["periphery"]?.state == .ran)
            #expect(outcome.statuses["periphery"]?.version == "3.29.0")
            #expect(outcome.statuses["periphery"]?.reason == note)
            #expect(outcome.report.warnings.contains(ScanWarning(file: nil, message: "periphery: " + note)))
        }
    }
}
