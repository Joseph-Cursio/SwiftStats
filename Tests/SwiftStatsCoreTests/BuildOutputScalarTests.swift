//
//  BuildOutputScalarTests.swift
//  SwiftStatsCoreTests
//
//  Build output read on Unicode scalars, not Characters (M7, design §6.1;
//  design B23 and B24, decided U13): a Prepend scalar (U+0600 to U+0605,
//  U+06DD) joins the scalar after it into one Character, and a combining
//  mark joins the one before it, but neither moves a field's boundary. A
//  place splits at its colons, a header at its `: ` separators, a message
//  keeps a mark just after the `: `, an ID's or a group's ` [` is found
//  after a Prepend scalar, and an escape sequence ends at its own last
//  scalar. A line is blank when every scalar is white space, and an
//  excerpt's `|`, a box's `+-`, a decoration, a group footnote's `]: <`
//  and a line prefix (`warning: `) are found among scalars, so a mark
//  after one doesn't hide it. All as the checker reads code points.
//

import Foundation
@testable import SwiftStatsCore
import Testing

/// The build output reader on lines holding a Prepend scalar or a
/// combining mark beside a separator or an escape sequence.
@Suite("Build output read on scalars")
struct BuildOutputScalarTests {
    /// A package root as the compiler spells it.
    private static let root = "/work/Pkg"

    /// The output of a build whose standard error is `stderr`, given as
    /// lines.
    private static func read(_ stderr: [String]) -> BuildOutput {
        BuildOutputReader.read(stderr: Data(stderr.map { $0 + "\n" }.joined().utf8), log: Data())
    }

    /// The scalars of each of `messages`: a String compares a lone mark,
    /// or `a` and a combining acute, canonically.
    private static func scalars(_ messages: [String]) -> [[Unicode.Scalar]] {
        messages.map { Array($0.unicodeScalars) }
    }

    @Test(
        """
        a Prepend scalar just before a timing place's colon stays in the path, and the line reads as its entry, \
        though the scalar joins the colon into one Character (design B23, decided U13)
        """,
        arguments: ["\u{600}", "\u{605}", "\u{6DD}"]
    )
    func prependBeforeTimingColon(prepend: String) {
        let path = "\(Self.root)/My Pkg:v2/A.swift" + prepend
        let output = Self.read(["1.00ms\t\(path):3:7", "2.00ms\t\(path):4:1\tglobal function f()@\(path):4:1"])
        #expect(output.unparsedTimingLines == 0)
        #expect(output.entries.map(\.place) == [
            BuildPlace(path: path, line: 3, column: 7),
            BuildPlace(path: path, line: 4, column: 1)
        ])
        #expect(output.entries.map(\.kind) == [.expression, .function])
    }

    @Test("""
        a Prepend scalar just before a place's colon stays in the path, and the place, the first one by the \
        first-match rule, is read on scalars, though the scalar joins the colon into one Character (design B23, \
        decided U13)
        """)
    func prependBeforePlaceColon() throws {
        let found = Self.read([
            "\(Self.root)/A.swift\u{600}:3:9: warning: w [variable_never_mutated]",
            "\(Self.root)/A.swift\u{6DD}:1:2: note: see \(Self.root)/B.swift:3:4: error: e [some_id]"
        ]).diagnostics
        try #require(found.count == 2)
        #expect(found[0].location == .file(BuildPlace(path: "\(Self.root)/A.swift\u{600}", line: 3, column: 9)))
        #expect(found[0].message == "w")
        #expect(found[0].identifier == "variable_never_mutated")
        #expect(found[1].location == .file(BuildPlace(path: "\(Self.root)/A.swift\u{6DD}", line: 1, column: 2)))
        #expect(found[1].severity == .note)
        #expect(found[1].message == "see \(Self.root)/B.swift:3:4: error: e")
    }

    @Test("""
        a combining mark just after the `: ` before a message starts the message, which keeps it, in every place \
        form (design B23, decided U13)
        """)
    func combiningMarkStartsMessage() throws {
        let found = Self.read([
            "\(Self.root)/A.swift:3:9: warning: \u{301}w [variable_never_mutated]",
            "<unknown>:0: error: \u{301}e",
            "macro expansion #expect:1:22: warning: \u{308}m [no_throw_in_try]"
        ]).diagnostics
        try #require(found.count == 3)
        #expect(found[0].location == .file(BuildPlace(path: "\(Self.root)/A.swift", line: 3, column: 9)))
        #expect(found[1].location == .unknown(line: 0))
        #expect(found[2].location == .macro(name: "#expect", line: 1, column: 22))
        #expect(Self.scalars(found.map(\.message)) == Self.scalars(["\u{301}w", "\u{301}e", "\u{308}m"]))
        #expect(found.map(\.identifier) == ["variable_never_mutated", nil, "no_throw_in_try"])
    }

    @Test("""
        a Prepend scalar just before an ID's or a group's ` [` leaves the suffix read, and the scalar ends the \
        message (design B23, decided U13)
        """)
    func prependBeforeSuffix() throws {
        let found = Self.read([
            "\(Self.root)/A.swift:3:9: warning: w\u{600} [variable_never_mutated] [#VariableNeverMutated]",
            "\(Self.root)/A.swift:4:9: warning: w [variable_never_mutated]\u{600} [#VariableNeverMutated]"
        ]).diagnostics
        try #require(found.count == 2)
        #expect(found.map(\.message) == ["w\u{600}", "w [variable_never_mutated]\u{600}"])
        #expect(found.map(\.identifier) == ["variable_never_mutated", nil])
        #expect(found.map(\.group) == ["VariableNeverMutated", "VariableNeverMutated"])
    }

    @Test("""
        a macro diagnostic's origin note whose path ends in a Prepend scalar gives its place (design B23, \
        decided U13)
        """)
    func prependInOriginNote() throws {
        let found = Self.read([
            "macro expansion #expect:1:22: warning: w [no_throw_in_try]",
            "`- \(Self.root)/Tests/T/T.swift\u{600}:33:36: note: expanded code originates here"
        ]).diagnostics
        let diagnostic = try #require(found.first)
        #expect(diagnostic.origin == BuildPlace(path: "\(Self.root)/Tests/T/T.swift\u{600}", line: 33, column: 36))
    }

    @Test(
        """
        an escape sequence just before a combining mark ends at its last scalar, so the mark is kept, and an OSC \
        whose text starts with one is still taken out whole (design B24, decided U13)
        """,
        arguments: [
            (written: "na\u{1B}[1;33m\u{301}ive", read: "na\u{301}ive"),
            (written: "na\u{1B}]8;;https://swift.org\u{1B}\\\u{301}ive", read: "na\u{301}ive"),
            (written: "na\u{1B}7\u{301}ive", read: "na\u{301}ive"),
            (written: "na\u{1B}]\u{301}8;;https://swift.org\u{07}ive", read: "naive")
        ]
    )
    func escapeBeforeCombiningMark(written: String, read: String) throws {
        let output = Self.read(["\(Self.root)/A.swift:4:9: warning: \(written) [pbd_never_used]"])
        #expect(output.escapedLines == 1)
        let diagnostic = try #require(output.diagnostics.first)
        #expect(Self.scalars([diagnostic.message]) == Self.scalars([read]))
        #expect(diagnostic.identifier == "pbd_never_used")
    }

    @Test(
        """
        a white space joined by a combining mark into one Character isn't blank, so the line continues a \
        message (decided U13)
        """,
        arguments: [" \u{301}", "\u{3000}\u{308}", "  \u{301} "]
    )
    func markedWhiteSpaceIsNotBlank(line: String) throws {
        let found = Self.read([
            "\(Self.root)/A.swift:3:9: warning: first line",
            line,
            "second line [some_id]"
        ]).diagnostics
        let diagnostic = try #require(found.first)
        #expect(found.count == 1)
        #expect(Self.scalars([diagnostic.message]) == Self.scalars(["first line\n\(line)\nsecond line"]))
        #expect(diagnostic.identifier == "some_id")
    }

    @Test(
        """
        an excerpt, box or decorated line is one by its scalars, though a combining mark follows its first `|`, \
        its `+-` or its decoration, so it ends an ID-less message (decided U13)
        """,
        arguments: ["   |\u{301} let x = 1", "  12 |\u{301} a | b", "  +-\u{301}----", "  `- \u{301}x", "`- \u{301}"]
    )
    func markedStructuralLineEndsMessage(line: String) throws {
        let found = Self.read([
            "\(Self.root)/A.swift:3:9: error: e",
            line,
            "\(Self.root)/A.swift:4:9: error: f [some_id]"
        ]).diagnostics
        try #require(found.count == 2)
        #expect(found.map(\.message) == ["e", "f"])
    }

    @Test("""
        a decorated origin note whose decoration a combining mark follows is the macro diagnostic's origin note, \
        not a diagnostic of its own (decided U13)
        """)
    func markedDecorationIsOriginNote() throws {
        let found = Self.read([
            "macro expansion #expect:1:22: warning: w [no_throw_in_try]",
            "`- \u{301}\(Self.root)/Tests/T/T.swift:33:36: note: expanded code originates here"
        ]).diagnostics
        let diagnostic = try #require(found.first)
        #expect(found.count == 1)
        #expect(diagnostic.origin == BuildPlace(path: "\u{301}\(Self.root)/Tests/T/T.swift", line: 33, column: 36))
    }

    @Test(
        """
        a line starting `warning: `, `error: `, `note: `, `remark: ` or `info: `, or a group footnote, is one by \
        its scalars, though a combining mark follows its prefix or its `]: <`: it ends an ID-less message, and a \
        `warning: ` line is counted (decided U13)
        """,
        arguments: [
            (line: "warning: \u{301}something odd", otherWarnings: 1),
            (line: "error: \u{301}boom", otherWarnings: 0),
            (line: "note: \u{301}n", otherWarnings: 0),
            (line: "remark: \u{301}r", otherWarnings: 0),
            (line: "info: \u{301}i", otherWarnings: 0),
            (line: "[#Group]: <\u{301}https://swift.org>", otherWarnings: 0)
        ]
    )
    func markedPrefixEndsMessage(line: String, otherWarnings: Int) throws {
        let output = Self.read(["\(Self.root)/A.swift:3:9: error: e", line])
        let diagnostic = try #require(output.diagnostics.first)
        #expect(output.diagnostics.count == 1)
        #expect(diagnostic.message == "e")
        #expect(output.otherWarningLines == otherWarnings)
    }
}
