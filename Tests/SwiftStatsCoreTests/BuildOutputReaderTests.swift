//
//  BuildOutputReaderTests.swift
//  SwiftStatsCoreTests
//
//  Reading the T1 build's output (M7, design §6.1): timing lines and their
//  times in hundredths, escapes, refused timing lines (a time past twelve
//  whole digits among them), each of which still ends a diagnostic's
//  message (design B10), a place's number edges, a line that isn't UTF-8,
//  and the recorded fixture build's output (`BuildDiagnosticTests` covers
//  the diagnostic grammar).
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

    /// Lines holding `ms<TAB>` that the timing grammar refuses: too many
    /// fraction digits, no digits, no column, an extra field, an empty
    /// declaration, text before the time, and a Prepend scalar before `ms`
    /// (it joins the `m` into one Character, but the mark is found on
    /// scalars, as the checker finds it; design U13).
    static let refusedTimings = [
        "4.355ms\t/work/Pkg/A.swift:1:2",
        "abcms\t/work/Pkg/A.swift:1:2",
        "4.35ms\t/work/Pkg/A.swift:1",
        "4.35ms\t/work/Pkg/A.swift:1:2\tgetter\textra",
        "4.35ms\t/work/Pkg/A.swift:1:2\t",
        "Compiling 4.35ms\t/work/Pkg/A.swift:1:2",
        "4.35\u{600}ms\t/work/Pkg/A.swift:1:2"
    ]

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

    @Test("a line holding a timing mark that the grammar refuses is counted, not read", arguments: refusedTimings)
    func refused(line: String) {
        let output = Self.read([line])
        #expect(output.entries.isEmpty)
        #expect(output.unparsedTimingLines == 1)
    }

    @Test(
        "a time with more than twelve whole digits is counted, not read, even one past what an Int holds",
        arguments: [
            "1000000000000ms\t<invalid loc>",
            "92233720368547759ms\t<invalid loc>",
            "92233720368547758.08ms\t<invalid loc>"
        ]
    )
    func overlongTime(line: String) {
        let output = Self.read([line])
        #expect(output.entries.isEmpty)
        #expect(output.unparsedTimingLines == 1)
    }

    @Test(
        "a time past twelve whole digits after a diagnostic ends its message and is counted, as a timing line does",
        arguments: [[], ["more [deprecated_declaration]"]]
    )
    func overlongTimeAfterDiagnostic(later: [String]) throws {
        let output = Self.read(["\(Self.root)/A.swift:1:2: warning: w", "1234567890123ms\t<invalid loc>"] + later)
        #expect(output.entries.isEmpty)
        #expect(output.unparsedTimingLines == 1)
        let diagnostic = try #require(output.diagnostics.first)
        #expect(diagnostic.message == "w")
    }

    @Test(
        "a refused timing line after a diagnostic ends its message and is counted, even when a later line holds an ID",
        arguments: refusedTimings, [[], ["more [deprecated_declaration]"]]
    )
    func refusedTimingAfterDiagnostic(line: String, later: [String]) throws {
        let output = Self.read(["\(Self.root)/A.swift:1:2: warning: w", line] + later)
        #expect(output.entries.isEmpty)
        #expect(output.unparsedTimingLines == 1)
        let diagnostic = try #require(output.diagnostics.first)
        #expect(output.diagnostics.count == 1)
        #expect(diagnostic.message == "w")
        #expect(diagnostic.identifier == nil)
    }

    @Test("a refused timing line inside a message keeps the lines before it, which a message with no ID takes")
    func refusedTimingInsideMessage() throws {
        let output = Self.read([
            "\(Self.root)/A.swift:1:2: warning: w",
            "second",
            "abcms\t\(Self.root)/A.swift:1:2",
            "third [deprecated_declaration]"
        ])
        #expect(output.unparsedTimingLines == 1)
        let diagnostic = try #require(output.diagnostics.first)
        #expect(diagnostic.message == "w\nsecond")
        #expect(diagnostic.identifier == nil)
    }

    @Test("in the task log a refused timing line also ends a diagnostic's message, and isn't counted")
    func refusedTimingInLog() throws {
        let output = Self.read([], log: [
            "\(Self.root)/A.swift:1:2: warning: w",
            "abcms\t\(Self.root)/A.swift:1:2",
            "more [deprecated_declaration]"
        ])
        #expect(output.unparsedTimingLines == 0)
        let diagnostic = try #require(output.diagnostics.first)
        #expect(diagnostic.message == "w")
        #expect(diagnostic.identifier == nil)
    }

    @Test("a place's line and column read 0 as a number, and one past what an Int holds as none, as the checker does")
    func placeNumberEdges() {
        let zero = Self.entry("1.00ms\t\(Self.root)/A.swift:0:0")
        #expect(zero?.place == BuildPlace(path: "\(Self.root)/A.swift", line: 0, column: 0))
        let past = Self.read(["1.00ms\t\(Self.root)/A.swift:9223372036854775808:1"])
        #expect(past.entries.isEmpty)
        #expect(past.unparsedTimingLines == 1)
    }

    @Test("a time with twelve whole digits reads exactly")
    func twelveDigitTime() {
        #expect(Self.entry("999999999999.99ms\t<invalid loc>")?.hundredths == 99_999_999_999_999)
        #expect(Self.entry("100000000000ms\t\(Self.root)/A.swift:1:2")?.hundredths == 10_000_000_000_000)
    }

    @Test("the task log is read for diagnostics only: its timing lines are neither entries nor counted")
    func taskLogTimings() {
        let output = Self.read([], log: ["4.35ms\t\(Self.root)/A.swift:1:2", "nonsense ms\tthing"])
        #expect(output.entries.isEmpty)
        #expect(output.unparsedTimingLines == 0)
    }

    @Test("a timing line that is also a diagnostic's first line is a diagnostic in the task log, an entry on stderr")
    func timingShapedHeader() throws {
        let line = "1ms\t<invalid loc>\tp:1:2: warning: m"
        let logged = Self.read([], log: [line])
        let diagnostic = try #require(logged.diagnostics.first)
        #expect(logged.diagnostics.count == 1 && logged.entries.isEmpty)
        #expect(diagnostic.severity == .warning && diagnostic.message == "m")
        #expect(diagnostic.location == .file(BuildPlace(path: "1ms\t<invalid loc>\tp", line: 1, column: 2)))
        let errors = Self.read([line])
        #expect(errors.diagnostics.isEmpty)
        #expect(errors.entries == [
            TimingEntry(kind: .function, hundredths: 100, place: nil, declaration: "p:1:2: warning: m")
        ])
    }

    @Test("a line ending with a carriage return reads as without it")
    func carriageReturn() {
        let output = BuildOutputReader.read(
            stderr: Data("1.00ms\t\(Self.root)/A.swift:1:2\r\n".utf8),
            log: Data()
        )
        #expect(output.entries.first?.place?.column == 2)
    }

    @Test("""
        a line that isn't UTF-8 is read as Latin-1 on its own: the lines around it, UTF-8 ones included, read \
        as they are
        """)
    func latin1Line() throws {
        var bytes = Data("0.20ms\t\(Self.root)/Caf\u{E9}.swift:1:2\n".utf8)
        // A byte that isn't UTF-8 (0xEF, Latin-1 ï) in a diagnostic and in
        // its excerpt line, between two timing lines, the first of which
        // holds UTF-8 é.
        bytes.append(Data("\(Self.root)/A.swift:2:3: warning: na".utf8))
        bytes.append(0xEF)
        bytes.append(Data("ve [pbd_never_used]\n2 | let na".utf8))
        bytes.append(0xEF)
        bytes.append(Data("ve = 1\n0.30ms\t\(Self.root)/A.swift:2:3\n".utf8))

        let output = BuildOutputReader.read(stderr: bytes, log: Data())

        #expect(output.entries.map(\.place?.path) == ["\(Self.root)/Caf\u{E9}.swift", "\(Self.root)/A.swift"])
        #expect(output.entries.map(\.hundredths) == [20, 30])
        let diagnostic = try #require(output.diagnostics.first)
        #expect(diagnostic.message == "na\u{EF}ve")
        #expect(diagnostic.identifier == "pbd_never_used")
        #expect(output.unparsedTimingLines == 0)
    }

    @Test("the recorded fixture build reads as its entries, its nine distinct diagnostics and its counters")
    func recordedFixture() throws {
        let fixture = try BuildFixture()
        defer { fixture.remove() }
        let output = try fixture.output()
        #expect(output.entries.count { $0.kind == .function } == 226)
        #expect(output.entries.count { $0.kind == .expression } == 381)
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

    @Test("""
        the recorded failed build's output, built one job at a time and normalised so it records the same on \
        every run, reads its entries and its dependency's warning
        """)
    func recordedFailure() throws {
        let fixture = try BuildFixture()
        defer { fixture.remove() }
        let output = BuildOutputReader.read(stderr: try fixture.recorded("failed.stderr"), log: Data())
        // Every target but IndexCore and its dependents compiled before
        // IndexCore's error: index-kit, index-support, IndexTool and
        // IndexDepKit.
        #expect(output.entries.count == 69)
        #expect(output.entries.allSatisfy { $0.hundredths == 1 })
        #expect(output.unparsedTimingLines == 0)
        #expect(output.diagnostics.map(\.identifier) == ["pbd_never_used"])
        #expect(output.otherWarningLines == 5)
    }
}
