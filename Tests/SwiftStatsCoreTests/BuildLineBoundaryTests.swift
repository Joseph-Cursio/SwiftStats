//
//  BuildLineBoundaryTests.swift
//  SwiftStatsCoreTests
//
//  The edges of the build output grammar's rules (M7, design §6.1), each
//  on the side that is easy to get wrong: a `|` with text before it, or
//  with digits that aren't ASCII before it, is no excerpt; a blank line of
//  a tab, a no-break or an ideographic space ends a message as a blank of
//  spaces does; white space after a message's ID, or at its end, is
//  dropped, but not inside it; a decorated line naming a place with the
//  origin text is an origin note only with severity `note`; a place needs
//  a path that doesn't start with white space, and a macro's name more
//  than its sigil; a header may end at its severity, its message empty;
//  and a CSI's intermediate bytes are part of the sequence.
//

import Foundation
@testable import SwiftStatsCore
import Testing

/// The build output reader on lines at the edge of a rule.
@Suite("Build line boundaries")
struct BuildLineBoundaryTests {
    /// A package root as the compiler spells it.
    private static let root = "/work/Pkg"

    /// The output of a build whose standard error is `stderr`, given as
    /// lines.
    private static func read(_ stderr: [String]) -> BuildOutput {
        BuildOutputReader.read(stderr: Data(stderr.map { $0 + "\n" }.joined().utf8), log: Data())
    }

    @Test("a header whose message holds a bar, and lines it takes holding one after text or other digits, read as text")
    func barsInText() throws {
        let found = Self.read([
            "\(Self.root)/A.swift:1:2: warning: use 'a || b' or a |= b here [some_id]",
            "\(Self.root)/A.swift:3:4: warning: first",
            "    x | y",
            "\u{661}\u{662} | arabic-indic digits",
            "  \u{FF13}| a fullwidth digit",
            "last [other_id]"
        ]).diagnostics
        try #require(found.count == 2)
        #expect(found[0].message == "use 'a || b' or a |= b here")
        #expect(found[0].identifier == "some_id")
        #expect(
            found[1].message
                == "first\n    x | y\n\u{661}\u{662} | arabic-indic digits\n  \u{FF13}| a fullwidth digit\nlast"
        )
        #expect(found[1].identifier == "other_id")
    }

    @Test(
        "a blank line of a tab, a no-break or an ideographic space ends a message, so the line after it isn't taken",
        arguments: ["\t", "\u{A0}", "\u{3000}", " \t "]
    )
    func otherBlankEndsMessage(blank: String) throws {
        let found = Self.read(["\(Self.root)/A.swift:1:2: warning: w", blank, "more"]).diagnostics
        let diagnostic = try #require(found.first)
        #expect(found.count == 1)
        #expect(diagnostic.message == "w")
        #expect(diagnostic.identifier == nil)
    }

    @Test("white space after a message's ID or at its end is dropped, and inside a joined message kept")
    func trailingWhiteSpace() {
        let found = Self.read([
            "\(Self.root)/A.swift:1:2: warning: w [pbd_never_used] ",
            "\(Self.root)/A.swift:3:4: warning: bare \u{A0}",
            "\(Self.root)/A.swift:5:6: warning: first  ",
            "second [some_id]\u{3000}"
        ]).diagnostics
        #expect(found.map(\.identifier) == ["pbd_never_used", nil, "some_id"])
        #expect(found.map(\.message) == ["w", "bare", "first  \nsecond"])
    }

    @Test(
        "a decorated line with the origin text and a severity other than note names no origin",
        arguments: ["warning", "error", "remark"]
    )
    func originNeedsNote(severity: String) throws {
        let found = Self.read([
            "macro expansion #expect:1:22: warning: w [no_throw_in_try]",
            "`- \(Self.root)/Tests/T/T.swift:33:36: \(severity): expanded code originates here"
        ]).diagnostics
        let diagnostic = try #require(found.first)
        #expect(found.count == 1)
        #expect(diagnostic.origin == nil)
    }

    @Test("an origin note whose text ends in spaces names its place")
    func paddedOriginNote() throws {
        let found = Self.read([
            "macro expansion #expect:1:22: warning: w [no_throw_in_try]",
            "`- \(Self.root)/Tests/T/T.swift:33:36: note: expanded code originates here  "
        ]).diagnostics
        let diagnostic = try #require(found.first)
        #expect(diagnostic.origin == BuildPlace(path: "\(Self.root)/Tests/T/T.swift", line: 33, column: 36))
    }

    @Test(
        "a header with a bare macro sigil, an empty path, or a path led by a tab or a no-break space is no diagnostic",
        arguments: [
            "macro expansion #:1:2: warning: w",
            "macro expansion @:1:2: warning: w",
            ":1:2: warning: w",
            "\t\(root)/A.swift:1:2: warning: w",
            "\u{A0}\(root)/A.swift:1:2: warning: w"
        ]
    )
    func refusedPlaces(line: String) {
        #expect(Self.read([line]).diagnostics.isEmpty)
    }

    @Test(
        "a timing line with an empty path or one led by a no-break space is counted, not read",
        arguments: ["1.00ms\t:1:2", "1.00ms\t\u{A0}\(root)/A.swift:1:2"]
    )
    func refusedTimingPlaces(line: String) {
        let output = Self.read([line])
        #expect(output.entries.isEmpty)
        #expect(output.unparsedTimingLines == 1)
    }

    @Test("a header ending at its severity is a diagnostic with an empty message, which takes the lines after it")
    func emptyMessage() throws {
        let found = Self.read([
            "\(Self.root)/A.swift:1:2: warning:",
            "\(Self.root)/A.swift:3:4: error:",
            "the reason [some_id]"
        ]).diagnostics
        try #require(found.count == 2)
        #expect(found[0].location == .file(BuildPlace(path: "\(Self.root)/A.swift", line: 1, column: 2)))
        #expect(found[0].message.isEmpty)
        #expect(found[1].severity == .error)
        #expect(found[1].message == "\nthe reason")
        #expect(found[1].identifier == "some_id")
    }

    @Test("a CSI with an intermediate byte is stripped whole, its final included")
    func intermediateByte() throws {
        let output = Self.read(["\(Self.root)/A.swift:1:2: warning: w\u{1B}[2 q [some_id]"])
        let diagnostic = try #require(output.diagnostics.first)
        #expect(diagnostic.message == "w")
        #expect(diagnostic.identifier == "some_id")
        #expect(output.escapedLines == 1)
    }
}
