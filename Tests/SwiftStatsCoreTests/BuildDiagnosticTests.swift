//
//  BuildDiagnosticTests.swift
//  SwiftStatsCoreTests
//
//  The diagnostic grammar of the T1 build's output (M7, design §6.1): IDs
//  and groups, the macro forms and their origin notes, continuation lines,
//  places read from the first prefix that is one, the lines counted rather
//  than read, and duplicates kept once.
//

import Foundation
@testable import SwiftStatsCore
import Testing

/// The build output reader's diagnostics, on hand-written lines.
@Suite("Build diagnostics")
struct BuildDiagnosticTests {
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

    /// The diagnostics of a standard error of `lines`.
    private static func diagnostics(_ lines: [String]) -> [BuildDiagnostic] {
        read(lines).diagnostics
    }

    @Test("a diagnostic's ID and group, its ID alone, or neither")
    func suffixes() throws {
        let found = Self.diagnostics([
            "\(Self.root)/A.swift:3:9: warning: variable 'constant' was never mutated [variable_never_mutated] "
                + "[#VariableNeverMutated]",
            "\(Self.root)/A.swift:16:5: warning: code after 'return' will never be executed "
                + "[unreachable_code_after_stmt]",
            "\(Self.root)/A.swift:36:59: warning: 'path' is deprecated: renamed to 'url' [#DeprecatedDeclaration]",
            "\(Self.root)/A.swift:40:1: warning: plain words [not an id]"
        ])
        #expect(found.map(\.identifier) == ["variable_never_mutated", "unreachable_code_after_stmt", nil, nil])
        #expect(found.map(\.group) == ["VariableNeverMutated", nil, "DeprecatedDeclaration", nil])
        #expect(found.map(\.message) == [
            "variable 'constant' was never mutated",
            "code after 'return' will never be executed",
            "'path' is deprecated: renamed to 'url'",
            "plain words [not an id]"
        ])
        let first = try #require(found.first)
        #expect(first.location == .file(BuildPlace(path: "\(Self.root)/A.swift", line: 3, column: 9)))
        #expect(first.severity == .warning)
    }

    @Test("a freestanding macro's diagnostic takes its origin note's place; without one it has none")
    func freestandingMacro() throws {
        let found = Self.diagnostics([
            "macro expansion #expect:1:22: warning: no calls to throwing functions occur within 'try' expression "
                + "[no_throw_in_try] [#UnnecessaryEffectMarker]",
            "`- \(Self.root)/Tests/T/T.swift:33:36: note: expanded code originates here",
            "31 |     /// the macro's expansion.",
            "macro expansion #expect:2:4: warning: lonely [no_throw_in_try]",
            "",
            "`- \(Self.root)/Tests/T/T.swift:40:1: note: expanded code originates here"
        ])
        try #require(found.count == 2)
        #expect(found[0].location == .macro(name: "#expect", line: 1, column: 22))
        #expect(found[0].origin == BuildPlace(path: "\(Self.root)/Tests/T/T.swift", line: 33, column: 36))
        #expect(found[0].identifier == "no_throw_in_try")
        #expect(found[0].group == "UnnecessaryEffectMarker")
        #expect(found[1].origin == nil)
    }

    @Test("an attached macro's diagnostic is read by the same form, its origin note decorated with a bar")
    func attachedMacro() throws {
        let found = Self.diagnostics([
            "macro expansion @Test:3:5: warning: a peer's warning [bridged_warning]",
            "   |- \(Self.root)/Tests/T/T.swift:12:6: note: expanded code originates here"
        ])
        let diagnostic = try #require(found.first)
        #expect(diagnostic.location == .macro(name: "@Test", line: 3, column: 5))
        #expect(diagnostic.origin == BuildPlace(path: "\(Self.root)/Tests/T/T.swift", line: 12, column: 6))
    }

    @Test("a message spanning lines is joined up to the line ending with its ID, as SIP's three-line warning")
    func continuation() throws {
        let output = Self.read([
            "\(Self.root)/Tests/T/CalleeReferenceTests.swift:89:36: warning: '#require(_:_:)' is redundant because "
                + "'Session(",
            "            name: \"spanning\"",
            "        )' never equals 'nil' (from macro 'require') [bridged_warning]",
            "38 |         let session = try? #require(Session(",
            "   |                                     `- warning: '#require(_:_:)' is redundant because 'Session(",
            "            name: \"spanning\"",
            "        )' never equals 'nil' (from macro 'require') [bridged_warning]"
        ])
        let diagnostic = try #require(output.diagnostics.first)
        #expect(output.diagnostics.count == 1)
        #expect(diagnostic.identifier == "bridged_warning")
        #expect(diagnostic.message == """
            '#require(_:_:)' is redundant because 'Session(
                        name: "spanning"
                    )' never equals 'nil' (from macro 'require')
            """)
        #expect(output.otherWarningLines == 0)
    }

    @Test("a message stops at an excerpt, a blank line, another diagnostic, a footnote or a warning line")
    func continuationStops() {
        let stops = [
            "12 | let x = 1",
            "",
            "\(Self.root)/A.swift:2:1: note: here",
            "[#NoUsage]: <https://docs.swift.org/compiler/documentation/diagnostics/no-usage>",
            "warning: \(Self.root)/A.swift:2:1 summary",
            "info: Building targets"
        ]
        for stop in stops {
            let found = Self.diagnostics(["\(Self.root)/A.swift:1:1: warning: no ID here", stop])
            #expect(found.first?.message == "no ID here", "stopped by \(stop)")
        }
        let long = ["\(Self.root)/A.swift:1:1: warning: start"] + (1...25).map { "more \($0)" }
        let joined = Self.diagnostics(long).first?.message.split(separator: "\n")
        #expect(joined?.count == BuildOutputReader.continuationLimit + 1)
    }

    @Test("a message ending with its ID takes no following line")
    func completeMessage() {
        let found = Self.diagnostics([
            "\(Self.root)/A.swift:1:1: warning: done [pbd_never_used]",
            "a stray line"
        ])
        #expect(found.first?.message == "done")
    }

    @Test("the place is the first prefix that reads as one, and <unknown> has a line only")
    func places() throws {
        let found = Self.diagnostics([
            "\(Self.root)/A.swift:1:2: warning: see \(Self.root)/B.swift:3:4: warning: inside [some_id]",
            "<unknown>:0: error: unable to open output file",
            "SwiftIfConfig.BuildConfiguration.isActiveTargetObjectFormat:3:15: note: requirement declared here"
        ])
        try #require(found.count == 3)
        #expect(found[0].location == .file(BuildPlace(path: "\(Self.root)/A.swift", line: 1, column: 2)))
        #expect(found[0].message == "see \(Self.root)/B.swift:3:4: warning: inside")
        #expect(found[1].location == .unknown(line: 0))
        #expect(found[1].severity == .error)
        let buffer = "SwiftIfConfig.BuildConfiguration.isActiveTargetObjectFormat"
        #expect(found[2].location == .file(BuildPlace(path: buffer, line: 3, column: 15)))
    }

    @Test("summary-form, excerpt, box and footnote lines are ignored; other warning lines are counted")
    func ignoredLines() {
        let output = Self.read([
            "warning: \(Self.root)/Sources/A/W.swift:19:10 remember to finish this [pound_warning]",
            "warning: 'index': /Toolchain/usr/bin/swift-frontend -frontend -c -primary-file "
                + "\(Self.root)/Package.swift",
            "warning: 'index': found 1 file(s) which are unhandled; explicitly declare them as resources",
            "19 | #warning(\"remember to finish this\")",
            "   |          `- warning: remember to finish this [pound_warning]",
            "   +--- macro expansion #expect ----------------------------------------",
            "   |1 | Testing.__checkValue(try layout(1) == 9)",
            "   |  |                      `- warning: no calls to throwing functions [no_throw_in_try]",
            "[#NoUsage]: <https://docs.swift.org/compiler/documentation/diagnostics/no-usage>",
            "error: Build failed"
        ])
        #expect(output.diagnostics.isEmpty)
        #expect(output.otherWarningLines == 3)
        #expect(output.entries.isEmpty)
    }

    @Test("a diagnostic printed in both files, or twice in one, is kept once")
    func duplicates() {
        let line = "\(Self.root)/A.swift:19:10: warning: remember to finish this [pound_warning]"
        let output = Self.read([line, line], log: [line])
        #expect(output.diagnostics.count == 1)
    }
}
