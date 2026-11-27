import Foundation
@testable import SwiftStatsCore
import Testing

/// How the build-output generator labels and writes fixed lines, each
/// expectation written by hand from `BuildOutputReader`'s,
/// `BuildLineGrammar`'s and `DiagnosticText`'s doc comments: the limit of
/// 20 continuation lines, the last line that completes a message, the
/// first-match rule, the origin note, the guards around wild lines and
/// malformed timing lines, line breaks and escapes, and the recorded lines
/// being real. A wrong label would make a property fail on a correct
/// reader, or pass a wrong one.
@Suite("Build output interpreter")
struct BuildOutputInterpreterTests {
    /// A message line and how its doc comment says it reads.
    struct SuffixReading: Sendable, CustomTestStringConvertible {
        /// The line.
        let text: SuffixedText
        /// Its message, without the suffixes read.
        let message: String
        /// The ID read; nil for none.
        let identifier: String?
        /// The group read; nil for none.
        let group: String?

        /// The line as written.
        var testDescription: String {
            text.rendered
        }

        /// The body `m` with its ID and group parts, read as `message`, `identifier` and
        /// `group`.
        init(
            _ identifierPart: SuffixedText.Part,
            _ groupPart: SuffixedText.Part,
            _ message: String,
            _ identifier: String?,
            _ group: String?
        ) {
            text = SuffixedText(body: "m", identifier: identifierPart, group: groupPart)
            self.message = message
            self.identifier = identifier
            self.group = group
        }
    }

    /// A file place for the examples.
    static let place = BuildPlace(path: "/p/a.swift", line: 3, column: 4)

    /// A plain line reading as `text`.
    static func plain(_ text: SuffixedText) -> BuildLineDraft {
        BuildLineDraft(.plain(text), text: text.rendered, traits: [])
    }

    /// A header at `place` with `severity` and `message`.
    static func header(
        _ message: SuffixedText,
        location: BuildDiagnostic.Location,
        severity: BuildDiagnostic.Severity
    ) -> BuildLineDraft {
        let prefix = switch location {
        case .file(let place):
            "\(place.path):\(place.line):\(place.column)"

        case let .macro(name, line, column):
            "macro expansion \(name):\(line):\(column)"

        case .unknown(let line):
            "<unknown>:\(line)"
        }
        let shape = BuildLineShape.header(location: location, severity: severity, message: message)
        return BuildLineDraft(shape, text: "\(prefix): \(severity.rawValue): \(message.rendered)", traits: [])
    }

    /// One file of `blocks`, written plain and terminated.
    static func file(_ blocks: [[BuildLineDraft]]) -> BuildFileDraft {
        BuildFileDraft(blocks: blocks, decorations: [], terminated: true)
    }

    @Test("a message takes at most 20 lines, so an ID on a later line is never read")
    func continuationLimit() {
        let lines = (1...21).map { Self.plain(SuffixedText("line\($0)")) }
            + [Self.plain(SuffixedText(body: "late", identifier: .valid("late_id"), group: .absent))]
        let drafts = [Self.header(SuffixedText("first"), location: .file(Self.place), severity: .warning)] + lines

        let labels = BuildOutputInterpreter.label(drafts, timings: true)

        let message = (["first"] + (1...20).map { "line\($0)" }).joined(separator: "\n")
        let diagnostic = BuildDiagnostic(
            severity: .warning,
            location: .file(Self.place),
            message: message,
            identifier: nil,
            group: nil,
            origin: nil
        )
        #expect(labels[0].reading == .diagnostic(diagnostic))
        #expect(labels[0].traits == [.crossesLimit, .noSuffix])
        #expect(labels[1...20].allSatisfy { $0.reading == .continuation })
        #expect(labels[21...].map(\.reading) == [.ignored, .ignored])
    }

    @Test("a message ends at the last line after which it is complete, keeping an inner suffix (M7 C2)")
    func lastCompletion() {
        let drafts = [
            Self.header(SuffixedText("first"), location: .file(Self.place), severity: .error),
            Self.plain(SuffixedText(body: "quoted", identifier: .valid("word"), group: .absent)),
            Self.plain(SuffixedText(body: "real", identifier: .valid("real_id"), group: .valid("Group"))),
            Self.plain(SuffixedText("after"))
        ]

        let labels = BuildOutputInterpreter.label(drafts, timings: true)

        let diagnostic = BuildDiagnostic(
            severity: .error,
            location: .file(Self.place),
            message: "first\nquoted [word]\nreal",
            identifier: "real_id",
            group: "Group",
            origin: nil
        )
        #expect(labels.map(\.reading) == [.diagnostic(diagnostic), .continuation, .continuation, .ignored])
        #expect(labels[0].traits == [.innerSuffix, .surplus])
    }

    @Test("a decoy place before the real one is the place, by the first-match rule")
    func decoyPlace() {
        let decoy = BuildOutputGen.FilePlace(
            text: "/d/b.swift:1:2",
            place: BuildPlace(path: "/d/b.swift", line: 1, column: 2),
            traits: []
        )
        let real = BuildOutputGen.HeaderPlace(text: "/p/a.swift:3:4", location: .file(Self.place), traits: [])
        let message = SuffixedText(body: "message", identifier: .valid("an_id"), group: .absent)

        let draft = BuildOutputGen.headerLine(
            place: real,
            severity: .warning,
            message: message,
            decoy: (decoy, .error)
        )

        let read = SuffixedText(body: "/p/a.swift:3:4: warning: message", identifier: .valid("an_id"), group: .absent)
        #expect(draft.text == "/d/b.swift:1:2: error: /p/a.swift:3:4: warning: message [an_id]")
        #expect(draft.shape == .header(location: .file(decoy.place), severity: .error, message: read))
        #expect(draft.traits == [.decoyPlace])
    }

    @Test("a macro diagnostic's origin is the note right after the lines its message took, and only that")
    func originNote() {
        let macro = BuildDiagnostic.Location.macro(name: "#expect", line: 1, column: 2)
        let note = "`- /p/a.swift:3:4: note: expanded code originates here"
        let origin = BuildLineDraft(.origin(Self.place), text: note, traits: [])
        let complete = SuffixedText(body: "done", identifier: .valid("an_id"), group: .absent)
        let openMacro = Self.header(SuffixedText("open"), location: macro, severity: .warning)
        let completeMacro = Self.header(complete, location: macro, severity: .warning)
        let afterTaken = [openMacro, Self.plain(complete), origin]
        let afterSurplus = [completeMacro, Self.plain(SuffixedText("more")), origin]
        let afterFile = [Self.header(complete, location: .file(Self.place), severity: .warning), origin]

        let origins = [afterTaken, afterSurplus, afterFile].map { drafts in
            BuildOutputInterpreter.message(at: 0, in: drafts)?.diagnostic.origin
        }

        #expect(origins == [Self.place, nil, nil])
    }

    @Test("a malformed timing line a message might take gets a blank line before it, or under the decided rules a mark")
    func malformedAfterHeader() {
        let malformed = BuildLineDraft(.malformedTiming, text: "1.234ms\t<invalid loc>", traits: [])
        let blocks = [[Self.header(SuffixedText("open"), location: .file(Self.place), severity: .warning)], [malformed]]

        let current = BuildOutputInterpreter.lines(of: Self.file(blocks), rules: .current, timings: true)
        let decided = BuildOutputInterpreter.lines(of: Self.file(blocks), rules: .decided, timings: true)

        #expect(current.map(\.text) == ["/p/a.swift:3:4: warning: open", "", "1.234ms\t<invalid loc>"])
        #expect(current.map { $0.traits.contains(.insertedBlank) } == [false, true, false])
        #expect(current.last?.reading == .unparsedTiming)
        #expect(decided.map(\.text) == ["/p/a.swift:3:4: warning: open", "1.234ms\t<invalid loc>"])
        #expect(decided.last?.traits.contains(.shapeB10) == true)
        #expect(decided.last?.reading == .unparsedTiming)
    }

    @Test("a wild line gets a blank line on each side and leaves the diagnostics unstated, the entries stated")
    func wildLine() {
        let entry = TimingEntry(kind: .expression, hundredths: 150, place: nil, declaration: nil)
        let timing = BuildLineDraft(.timing(entry), text: "1.5ms\t<invalid loc>", traits: [])
        let wild = BuildLineDraft(wildBytes: [UInt8(ascii: "a"), 0xFF, UInt8(ascii: "b")])
        let output = GeneratedBuildOutput(rules: .current, stderr: Self.file([[timing], [wild]]), log: Self.file([]))

        #expect(output.stderrLines.map(\.reading) == [.entry(entry), .skipped, .unstated, .skipped])
        #expect(output.stderrLines[2].traits == [.invalidUTF8])
        #expect(output.entries == [entry])
        #expect(output.expected == nil)
    }

    @Test("a line ends with CRLF only when its decoration asks, and the last only lacks a line break when not empty")
    func lineBreaks() {
        let blank = BuildLineDraft(.blank, text: "", traits: [])
        let word = Self.plain(SuffixedText("word"))
        let crlf = BuildLineDecoration(carriageReturn: true, escape: nil)
        let open = BuildFileDraft(blocks: [[word], [word]], decorations: [crlf], terminated: false)
        let emptyLast = BuildFileDraft(blocks: [[word], [blank]], decorations: [], terminated: false)

        let openLines = BuildOutputInterpreter.lines(of: open, rules: .current, timings: true)
        let emptyLines = BuildOutputInterpreter.lines(of: emptyLast, rules: .current, timings: true)

        #expect(openLines.map(\.lineBreak) == ["\r\n", ""])
        let breakTraits = openLines.map { $0.traits.intersection([.carriageReturnLineFeed, .unterminated]) }
        #expect(breakTraits == [[.carriageReturnLineFeed], [.unterminated]])
        #expect(emptyLines.map(\.lineBreak) == ["\n", "\n"])
    }

    @Test("escapes are written whole at Character boundaries, and one joining the Character after it moves to the end")
    func escapes() {
        let csi = BuildLineDecoration.Escape.csi(start: 1, end: 2)
        let joining = "a\u{0}\u{301}b"
        let atMark = BuildLineDecoration.Escape.twoCharacter(2)

        let wrapped = BuildLineDecoration.written("abc", escape: csi, keepJoins: false)
        let moved = BuildLineDecoration.written(joining, escape: atMark, keepJoins: false)
        let kept = BuildLineDecoration.written(joining, escape: atMark, keepJoins: true)

        #expect(wrapped.bytes == Array("a\u{1B}[1;33mb\u{1B}[0mc".utf8))
        #expect(wrapped.joinsKept == false)
        #expect(moved.bytes == Array((joining + "\u{1B}7").utf8))
        #expect(moved.joinsKept == false)
        #expect(kept.bytes == Array("a\u{0}\u{1B}7\u{301}b".utf8))
        #expect(kept.joinsKept)
    }

    @Test("suffix parts read as DiagnosticText's doc comment states", arguments: [
        SuffixReading(.valid("an_id"), .absent, "m", "an_id", nil),
        SuffixReading(.valid("an_id"), .valid("Group"), "m", "an_id", "Group"),
        SuffixReading(.malformed(" [Bad]"), .valid("Group"), "m [Bad]", nil, "Group"),
        SuffixReading(.valid("an_id"), .malformed(" [#]"), "m [an_id] [#]", nil, nil),
        SuffixReading(.malformed(" []"), .absent, "m []", nil, nil)
    ])
    func suffixParts(reading: SuffixReading) {
        #expect(reading.text.readMessage == reading.message)
        #expect(reading.text.readIdentifier == reading.identifier)
        #expect(reading.text.readGroup == reading.group)
        #expect(reading.text.isComplete == (reading.identifier != nil || reading.group != nil))
    }

    @Test("every recorded line is a line of the Index fixture's recordings")
    func recordedLines() throws {
        let names = ["build.stderr", "rebuild.stderr", "failed.stderr", "build.stdout"]
        let recordings = try names.map(IndexFixture.text)
        let lines = Set(recordings.flatMap { recording in
            recording.split(separator: "\n", omittingEmptySubsequences: false).map(String.init)
        })
        let recorded = (BuildOutputGen.recordedGroups + BuildOutputGen.recordedTimings).flatMap(\.self)

        #expect(recorded.filter { lines.contains($0.text) == false }.map(\.text).isEmpty)
        #expect(recorded.allSatisfy { $0.traits.contains(.recorded) })
    }
}
