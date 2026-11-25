//
//  BuildOutputReaderTests.swift
//  SwiftStatsCoreTests
//
//  Reading the T1 build's output (M7, design §6.1): timing lines and their
//  times in hundredths, escapes, refused timing lines, and the recorded
//  fixture build's output (`BuildDiagnosticTests` covers the diagnostic
//  grammar).
//

import Foundation
@testable import SwiftStatsCore
import Testing

/// The build output reader, on hand-written lines and on the Index
/// fixture's recorded build.
@Suite("Build output reader")
struct BuildOutputReaderTests {
    /// A package root as the compiler spells it.
    private static let root = "/work/Pkg"

    /// The output of a build whose standard error is `stderr` and whose
    /// task log is `log`, each given as lines.
    private static func read(_ stderr: [String], log: [String] = []) -> BuildOutput {
        BuildOutputReader.read(
            stderr: Data(stderr.map { $0 + "\n" }.joined().utf8),
            log: Data(log.map { $0 + "\n" }.joined().utf8)
        )
    }

    /// The single entry of a standard error holding only `line`.
    private static func entry(_ line: String) -> TimingEntry? {
        let output = read([line])
        return output.entries.count == 1 ? output.entries.first : nil
    }

    @Test("times read as hundredths of a millisecond with two decimals, one or none")
    func times() throws {
        let place = BuildPlace(path: "\(Self.root)/Sources/A/A.swift", line: 3, column: 7)
        let two = try #require(Self.entry("4.35ms\t\(Self.root)/Sources/A/A.swift:3:7"))
        #expect(two == TimingEntry(kind: .expression, hundredths: 435, place: place, declaration: nil))
        #expect(Self.entry("4.3ms\t\(Self.root)/Sources/A/A.swift:3:7")?.hundredths == 430)
        #expect(Self.entry("4ms\t\(Self.root)/Sources/A/A.swift:3:7")?.hundredths == 400)
        #expect(Self.entry("0.01ms\t\(Self.root)/Sources/A/A.swift:3:7")?.hundredths == 1)
        #expect(Self.entry("125.07ms\t\(Self.root)/Sources/A/A.swift:3:7")?.hundredths == 12_507)
    }

    @Test("a function body's line keeps its declaration, and a synthesized member has no place")
    func functionLines() throws {
        let declaration = "global function A.(file).first()@\(Self.root)/Sources/A/A.swift:2:13"
        let body = try #require(Self.entry("0.59ms\t\(Self.root)/Sources/A/A.swift:2:13\t\(declaration)"))
        #expect(body.kind == .function)
        #expect(body.declaration == declaration)
        #expect(body.place == BuildPlace(path: "\(Self.root)/Sources/A/A.swift", line: 2, column: 13))
        let synthesized = try #require(
            Self.entry("0.19ms\t<invalid loc>\tinstance method A.(file).Index extension.hash(into:)")
        )
        #expect(synthesized.place == nil)
        #expect(synthesized.kind == .function)
        #expect(Self.entry("0.05ms\t<invalid loc>")?.place == nil)
    }

    @Test("a macro buffer and a path holding spaces and colons are read from the right")
    func oddPaths() {
        #expect(
            Self.entry("0.29ms\t@__swiftmacro_14IndexCoreTestsAAV04onlyC04TestfMp_.swift:25:141")?.place
                == BuildPlace(path: "@__swiftmacro_14IndexCoreTestsAAV04onlyC04TestfMp_.swift", line: 25, column: 141)
        )
        #expect(
            Self.entry("1.00ms\t/work/My Pkg:v2/Sources/A b/A:c.swift:10:4")?.place
                == BuildPlace(path: "/work/My Pkg:v2/Sources/A b/A:c.swift", line: 10, column: 4)
        )
    }

    @Test("a coloured line is read without its escapes, and counted")
    func escapes() throws {
        let output = Self.read([
            "\u{1B}[1m\(Self.root)/A.swift:4:9: \u{1B}[35mwarning: \u{1B}[0mnever used [pbd_never_used] "
                + "[#\u{1B}]8;;https://docs.swift.org/x\u{07}NoUsage\u{1B}]8;;\u{07}]",
            "0.10ms\t\(Self.root)/A.swift:4:9"
        ])
        #expect(output.escapedLines == 1)
        let diagnostic = try #require(output.diagnostics.first)
        #expect(diagnostic.message == "never used")
        #expect(diagnostic.identifier == "pbd_never_used")
        #expect(diagnostic.group == "NoUsage")
        #expect(output.entries.count == 1)
    }

    @Test(
        "a line holding a timing mark that the grammar refuses is counted, not read",
        arguments: [
            "4.355ms\t/work/Pkg/A.swift:1:2",
            "abcms\t/work/Pkg/A.swift:1:2",
            "4.35ms\t/work/Pkg/A.swift:1",
            "4.35ms\t/work/Pkg/A.swift:1:2\tgetter\textra",
            "4.35ms\t/work/Pkg/A.swift:1:2\t",
            "Compiling 4.35ms\t/work/Pkg/A.swift:1:2"
        ]
    )
    func refused(line: String) {
        let output = Self.read([line])
        #expect(output.entries.isEmpty)
        #expect(output.unparsedTimingLines == 1)
    }

    @Test("the task log is read for diagnostics only: its timing lines are neither entries nor counted")
    func taskLogTimings() {
        let output = Self.read([], log: ["4.35ms\t\(Self.root)/A.swift:1:2", "nonsense ms\tthing"])
        #expect(output.entries.isEmpty)
        #expect(output.unparsedTimingLines == 0)
    }

    @Test("a line ending with a carriage return reads as without it")
    func carriageReturn() {
        let output = BuildOutputReader.read(
            stderr: Data("1.00ms\t\(Self.root)/A.swift:1:2\r\n".utf8),
            log: Data()
        )
        #expect(output.entries.first?.place?.column == 2)
    }

    @Test("the recorded fixture build reads as its entries, its nine distinct diagnostics and its counters")
    func recordedFixture() throws {
        let fixture = try BuildFixture()
        defer { fixture.remove() }
        let output = try fixture.output()
        #expect(output.entries.count { $0.kind == .function } == 213)
        #expect(output.entries.count { $0.kind == .expression } == 377)
        #expect(output.unparsedTimingLines == 0)
        #expect(output.escapedLines == 0)
        // Two manifest commands, two SwiftPM package warnings, one summary form.
        #expect(output.otherWarningLines == 5)
        #expect(output.diagnostics.count == 9)
        #expect(output.diagnostics.allSatisfy { $0.severity == .warning })
        // The unused `let` in IndexDep and in `Locals.swift`: one ID, two places.
        #expect(output.diagnostics.compactMap(\.identifier).sorted() == [
            "availability_deprecated", "bridged_warning", "no_throw_in_try", "nonoptional_compare_to_nil",
            "pbd_never_used", "pbd_never_used", "pound_warning", "unreachable_code_after_stmt",
            "variable_never_mutated"
        ])
        let macro = try #require(output.diagnostics.first { $0.identifier == "no_throw_in_try" })
        let tests = fixture.root + "/Tests/IndexCoreTests/IndexCoreTests.swift"
        #expect(macro.origin == BuildPlace(path: tests, line: 33, column: 36))
        let bridged = try #require(output.diagnostics.first { $0.identifier == "bridged_warning" })
        #expect(bridged.message.split(separator: "\n").count == 3)
    }

    @Test("the recorded failed build's output reads its entries and its dependency's warning")
    func recordedFailure() throws {
        let fixture = try BuildFixture()
        defer { fixture.remove() }
        let output = BuildOutputReader.read(stderr: try fixture.recorded("failed.stderr"), log: Data())
        #expect(output.entries.count == 16)
        #expect(output.unparsedTimingLines == 0)
        #expect(output.diagnostics.map(\.identifier) == ["pbd_never_used"])
        #expect(output.otherWarningLines == 5)
    }
}
