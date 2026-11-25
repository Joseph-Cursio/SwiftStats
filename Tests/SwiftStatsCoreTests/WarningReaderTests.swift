//
//  WarningReaderTests.swift
//  SwiftStatsCoreTests
//
//  The T1 build's warnings as `swiftc` findings (M7, design §6.3): rules
//  from diagnostic IDs, categories from groups, macro warnings at their
//  origin notes, duplicates collapsed, places outside the package dropped,
//  places in plugin targets counted apart, and the recorded fixture
//  build's eight own warnings.
//

import Foundation
@testable import SwiftStatsCore
import Testing

/// The warning reader, on the Index fixture's recorded build and on
/// hand-written diagnostics.
@Suite("Warning reader")
struct WarningReaderTests {
    /// A package with a library and a plugin target, measured.
    private struct Plugged {
        /// The package.
        let package: TemporaryPackage
        /// Its measurements.
        let measured: ScanMeasurements
        /// Its targets.
        let targets: [TargetSummary]
        /// Its root, as its real path.
        let root: String

        /// A warning reader for the package, the files `changedFiles`
        /// changed.
        func reader(changedFiles: Set<String>) -> WarningReader {
            WarningReader(
                measured: measured,
                targets: targets,
                root: root,
                build: root + "/.swiftstats/index-build",
                changedFiles: changedFiles
            )
        }
    }

    /// A finding's rule, category, file, line and column.
    private struct Identity: Hashable {
        /// The rule.
        let rule: String
        /// The category.
        let category: String?
        /// The file.
        let file: String
        /// The line.
        let line: Int?
        /// The column.
        let column: Int?
    }

    /// The package: a library `Lib` and a plugin `Gen`.
    private static func plugged() throws -> Plugged {
        let targets = [
            DescribedTarget(
                name: "Lib",
                type: "library",
                moduleType: "SwiftTarget",
                path: "Sources/Lib",
                sources: ["Lib.swift"]
            ),
            DescribedTarget(
                name: "Gen",
                type: "plugin",
                moduleType: "PluginTarget",
                path: "Plugins/Gen",
                sources: ["plugin.swift"]
            )
        ]
        let package = try TemporaryPackage(
            [
                "Sources/Lib/Lib.swift": "public func value() -> Int {\n    let unused = 1\n    return 2\n}\n",
                "Plugins/Gen/plugin.swift": "let path = 1\n"
            ],
            targets: targets
        )
        let resolved = TargetResolver.resolve(DescribedPackage(name: "Probe", targets: targets))
        let measured = PackageScanner.measure(resolved, root: package.root, configuration: SwiftStatsConfiguration())
        return Plugged(
            package: package,
            measured: measured,
            targets: resolved,
            root: BuildFixture.realPath(package.root)
        )
    }

    /// A warning at `line` and `column` of `path`, with `identifier` and
    /// `message`.
    private static func warning(
        _ path: String,
        line: Int,
        column: Int,
        identifier: String?,
        message: String = "a warning"
    ) -> BuildDiagnostic {
        BuildDiagnostic(
            severity: .warning,
            location: .file(BuildPlace(path: path, line: line, column: column)),
            message: message,
            identifier: identifier,
            group: nil,
            origin: nil
        )
    }

    /// The identities of `findings`.
    private static func identities(_ findings: [RawFinding]) -> Set<Identity> {
        Set(findings.map { finding in
            let place = finding.places.first
            return Identity(
                rule: finding.rule,
                category: finding.category,
                file: place?.file ?? "",
                line: place?.line,
                column: place?.column
            )
        })
    }

    @Test("the recorded build's own warnings become swiftc findings, the dependency's dropped")
    func recordedWarnings() throws {
        let fixture = try BuildFixture()
        defer { fixture.remove() }
        let read = fixture.warningReader(changedFiles: []).read(try fixture.output().diagnostics)
        let warnings = "Sources/IndexCore/Warnings.swift"
        let locals = "Sources/IndexCore/Locals.swift"
        let tests = "Tests/IndexCoreTests/IndexCoreTests.swift"
        #expect(Self.identities(read.findings) == [
            Identity(rule: "pound_warning", category: nil, file: warnings, line: 19, column: 10),
            Identity(
                rule: "availability_deprecated",
                category: "DeprecatedDeclaration",
                file: warnings,
                line: 4,
                column: 23
            ),
            Identity(
                rule: "variable_never_mutated",
                category: "VariableNeverMutated",
                file: warnings,
                line: 3,
                column: 9
            ),
            Identity(rule: "unreachable_code_after_stmt", category: nil, file: warnings, line: 16, column: 5),
            Identity(rule: "pbd_never_used", category: "NoUsage", file: locals, line: 26, column: 9),
            Identity(rule: "nonoptional_compare_to_nil", category: nil, file: tests, line: 27, column: 23),
            Identity(rule: "no_throw_in_try", category: "UnnecessaryEffectMarker", file: tests, line: 33, column: 36),
            Identity(rule: "bridged_warning", category: nil, file: tests, line: 38, column: 37)
        ])
        // `pound_warning` is printed twice and kept once.
        #expect(read.findings.count == 8)
        #expect(read.dropped == 1)
        #expect(read.unmapped == 0)
        #expect(read.plugin == 0)
        #expect(read.findings.allSatisfy { finding in
            finding.tool == "swiftc" && finding.kind == .defect && finding.severity == "warning"
                && finding.symbol == nil
        })
        let bridged = try #require(read.findings.first { $0.rule == "bridged_warning" })
        #expect(bridged.message.split(separator: "\n").count == 3)
        #expect(bridged.message.hasSuffix("never equals 'nil' (from macro 'require')"))
        let macro = try #require(read.findings.first { $0.rule == "no_throw_in_try" })
        let location = try #require(FindingMapper(measured: fixture.measured).finding(for: macro).locations.first)
        #expect(location.attachedTo == .function)
        #expect(location.owner == "IndexCoreTests::IndexCoreTests::func needlessTry()")
    }

    @Test("places under the build directory or outside the root are dropped, once per place and ID")
    func dropped() throws {
        let plugged = try Self.plugged()
        defer { plugged.package.remove() }
        let build = plugged.root + "/.swiftstats/index-build/checkouts/Dep/Dep.swift"
        let read = plugged.reader(changedFiles: []).read([
            Self.warning(build, line: 1, column: 1, identifier: "pbd_never_used"),
            Self.warning(build, line: 1, column: 1, identifier: "pbd_never_used", message: "another copy"),
            Self.warning("/elsewhere/IndexDep/Sources/A.swift", line: 4, column: 9, identifier: "pbd_never_used")
        ])
        #expect(read.findings.isEmpty)
        #expect(read.dropped == 2)
    }

    @Test("copies of one warning at one place collapse on its ID, or its message when it has none")
    func duplicates() throws {
        let plugged = try Self.plugged()
        defer { plugged.package.remove() }
        let file = plugged.root + "/Sources/Lib/Lib.swift"
        let read = plugged.reader(changedFiles: []).read([
            Self.warning(file, line: 2, column: 9, identifier: "pbd_never_used", message: "first wording"),
            Self.warning(file, line: 2, column: 9, identifier: "pbd_never_used", message: "second wording"),
            Self.warning(file, line: 2, column: 9, identifier: "other_id"),
            Self.warning(file, line: 2, column: 9, identifier: nil, message: "plain"),
            Self.warning(file, line: 2, column: 9, identifier: nil, message: "plain")
        ])
        #expect(read.findings.map(\.rule) == ["other_id", "pbd_never_used", "unidentified"])
        #expect(read.findings.first { $0.rule == "pbd_never_used" }?.message == "first wording")
    }

    @Test("a place in a file the scan didn't parse is kept, and FindingMapper marks it unscanned")
    func unscanned() throws {
        let plugged = try Self.plugged()
        defer { plugged.package.remove() }
        let read = plugged.reader(changedFiles: []).read([
            Self.warning(plugged.root + "/Sources/Lib/Unlisted.swift", line: 3, column: 1, identifier: "pbd_never_used")
        ])
        let finding = try #require(read.findings.first)
        let location = FindingMapper(measured: plugged.measured).finding(for: finding).locations.first
        #expect(location?.attachedTo == .unscanned)
    }

    @Test("a place in a plugin target is a finding counted apart")
    func pluginTarget() throws {
        let plugged = try Self.plugged()
        defer { plugged.package.remove() }
        let read = plugged.reader(changedFiles: []).read([
            Self.warning(plugged.root + "/Plugins/Gen/plugin.swift", line: 1, column: 5, identifier: nil),
            Self.warning(plugged.root + "/Plugins/Gen/Helper.swift", line: 2, column: 5, identifier: nil),
            Self.warning(plugged.root + "/Sources/Lib/Lib.swift", line: 2, column: 9, identifier: "pbd_never_used")
        ])
        #expect(read.plugin == 2)
        #expect(read.findings.count == 3)
        #expect(read.findings.filter { $0.places.first?.file.hasPrefix("Plugins/") == true }.map(\.rule)
            == ["unidentified", "unidentified"])
    }

    @Test("a warning with no place in a file, or in a file that changed during the scan, is unmapped")
    func unmapped() throws {
        let plugged = try Self.plugged()
        defer { plugged.package.remove() }
        let file = plugged.root + "/Sources/Lib/Lib.swift"
        let macro = BuildDiagnostic(
            severity: .warning,
            location: .macro(name: "#expect", line: 1, column: 22),
            message: "no origin",
            identifier: "no_throw_in_try",
            group: nil,
            origin: nil
        )
        let unknown = BuildDiagnostic(
            severity: .warning,
            location: .unknown(line: 0),
            message: "nowhere",
            identifier: nil,
            group: nil,
            origin: nil
        )
        let read = plugged.reader(changedFiles: ["Sources/Lib/Lib.swift"]).read([
            macro,
            unknown,
            Self.warning(file, line: 2, column: 9, identifier: "pbd_never_used")
        ])
        #expect(read.findings.isEmpty)
        #expect(read.unmapped == 3)
    }

    @Test("errors, notes and remarks are not findings")
    func otherSeverities() throws {
        let plugged = try Self.plugged()
        defer { plugged.package.remove() }
        let place = BuildPlace(path: plugged.root + "/Sources/Lib/Lib.swift", line: 2, column: 9)
        let severities: [BuildDiagnostic.Severity] = [.error, .note, .remark]
        let read = plugged.reader(changedFiles: []).read(severities.map { severity in
            BuildDiagnostic(
                severity: severity,
                location: .file(place),
                message: "not a warning",
                identifier: "some_id",
                group: nil,
                origin: nil
            )
        })
        #expect(read == WarningReader.Read(findings: [], dropped: 0, unmapped: 0, plugin: 0))
    }
}
