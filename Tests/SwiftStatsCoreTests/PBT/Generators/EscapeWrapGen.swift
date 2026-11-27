//
//  EscapeWrapGen.swift
//  SwiftStatsCoreTests
//
//  Generated build output with escape sequences written into some of its
//  lines, for P1.6. A line is wrapped only when it holds no escape and is
//  UTF-8 (wild lines of any scalars included, whose reading isn't stated:
//  the law compares two readings, not a label), and only by whole
//  sequences: a CSI colour and its reset, a CSI with an intermediate byte,
//  an OSC-8 link ended by BEL or by `ESC \`, a two-character escape, or a
//  sequence cut off at the line's
//  end. Sequences go at Unicode scalar boundaries, not only Character
//  ones (decided U13, which widened the law, B24): about half go just
//  before a scalar that joins the scalar before it (a combining mark, a
//  zero-width joiner, an emoji modifier) when the line has one, so the
//  sequence's last scalar joins it into one Character; the rest go at any
//  scalar boundary, inside a Character, after a Prepend scalar or between
//  jamo included. Generated lines rarely hold a joining scalar, so a third
//  of the wraps first write one into the line, where their first sequence
//  then goes: in the line as read without the wrap too, so both readings
//  the law compares see the same text. A quarter of the wraps likewise
//  write a backslash into the line just after their last sequence (but a
//  cut-off one, which a backslash would end): after a BEL-ended OSC it is
//  text, where after `ESC` it would end the OSC. No sequence or scalar goes before
//  a byte order mark that starts a line: the reader decodes each line with
//  Foundation, which drops a mark there and keeps one anywhere else, so a
//  sequence before it would change the line's text (outside P1.6's law;
//  no build prints one). So the wrap decodes each line's scalars with the
//  standard library, which keeps the mark, and its plain side is the line
//  as generated. Lines and positions are drawn as
//  numbers and taken modulo the lines both files have and the places a
//  line has, so any wrap fits any output and line; at most 30 wraps are
//  drawn (design D7's array cap, which bounds the engine's shrink), and
//  the engine shrinks the list by dropping wraps.
//

import Foundation
import PropertyBased
import Testing

/// Generators of build output with escapes written into its lines.
enum EscapeWrapGen {
    /// The escape sequences a wrap writes.
    enum Kind: CaseIterable, Hashable, Sendable {
        /// A CSI colour, and its reset after it.
        case csi
        /// A CSI with an intermediate byte (a cursor style).
        case cursorStyle
        /// An OSC-8 link ended by BEL, and its end.
        case oscBell
        /// An OSC-8 link ended by `ESC \`, and its end.
        case oscTerminated
        /// A sequence cut off at the end of the line.
        case truncated
        /// A two-character escape.
        case twoCharacter
    }

    /// How one line is wrapped.
    struct Wrap: Hashable, Sendable {
        /// The line wrapped, by its index in both files, standard error's
        /// first, modulo their line count.
        let line: Int
        /// The sequences written.
        let kind: Kind
        /// Where the first sequence goes, modulo the places it can go.
        let start: Int
        /// Where the second goes, modulo, and never before the first.
        let end: Int
        /// Whether the sequences go just before a scalar that joins the
        /// scalar before it, when the line has one: a combining mark, a
        /// zero-width joiner, an emoji modifier.
        let beforeJoiner: Bool
        /// The joining scalar written into the line first, at `start`, by
        /// its index in `EscapeWrapGen.joiningScalars`; nil for none.
        let joiner: Int?
        /// Whether a backslash is written into the line just after the
        /// last sequence, when it isn't a cut-off one.
        let backslash: Bool
    }

    /// One line, as read without its wrap and as wrapped.
    struct WrappedLine: Hashable, Sendable {
        /// The line's bytes without the wrap's sequences (a joining scalar
        /// it wrote included), its line break included.
        let plain: Data
        /// The line's bytes as wrapped, its line break included.
        let data: Data
        /// Whether a wrap wrote sequences into it.
        let isWrapped: Bool
        /// Whether a sequence went inside a Character of its text.
        let isInsideCharacter: Bool
        /// Whether a sequence's last scalar joins the scalar after it into
        /// one Character (B24's shape).
        let joins: Bool
    }

    /// A generated output and the wraps of its lines, P1.6's input.
    struct Wrapped: Sendable, CustomTestStringConvertible {
        /// The output as generated.
        let original: GeneratedBuildOutput
        /// The wraps, each of the line its `line` names; a line named by
        /// several takes the first, and a line named by none is left as
        /// written.
        let wraps: [Wrap]

        /// The standard error's lines, as read without their wraps and as
        /// wrapped.
        var stderrLines: [WrappedLine] {
            original.stderrLines.indices.map { EscapeWrapGen.wrapped(original.stderrLines[$0], by: wrap(at: $0)) }
        }

        /// The task log's lines, as read without their wraps and as
        /// wrapped.
        var logLines: [WrappedLine] {
            let offset = original.stderrLines.count
            return original.logLines.indices.map { index in
                EscapeWrapGen.wrapped(original.logLines[index], by: wrap(at: offset + index))
            }
        }

        /// The standard error's bytes without the wraps' sequences.
        var plainStderr: Data {
            Data(stderrLines.flatMap(\.plain))
        }

        /// The task log's bytes without the wraps' sequences.
        var plainLog: Data {
            Data(logLines.flatMap(\.plain))
        }

        /// The standard error's bytes, as wrapped.
        var stderr: Data {
            Data(stderrLines.flatMap(\.data))
        }

        /// The task log's bytes, as wrapped.
        var log: Data {
            Data(logLines.flatMap(\.data))
        }

        /// How many lines a wrap wrote sequences into.
        var newlyWrapped: Int {
            (stderrLines + logLines).count(where: \.isWrapped)
        }

        /// Whether a line was wrapped in an OSC-8 link ended by BEL with a
        /// backslash written just after its last sequence.
        var bellBeforeBackslash: Bool {
            let lines = stderrLines + logLines
            return lines.indices.contains { index in
                lines[index].isWrapped && wrap(at: index).map { $0.kind == .oscBell && $0.backslash } == true
            }
        }

        /// How many lines both files have.
        var lineCount: Int {
            original.stderrLines.count + original.logLines.count
        }

        /// The output and each wrap with the line it wraps, in ASCII.
        var testDescription: String {
            let count = lineCount
            let listed = wraps.map { "  line \(count == 0 ? "none" : String($0.line % count)): \($0)" }
            return PBTTrace.ascii((["wraps:"] + listed).joined(separator: "\n") + "\n" + original.testDescription)
        }

        /// The wrap of the line at `index` of both files, if any: the first
        /// that names it.
        func wrap(at index: Int) -> Wrap? {
            let count = lineCount
            guard count > 0 else {
                return nil
            }
            return wraps.first { $0.line % count == index }
        }
    }

    /// How many wraps are drawn (forced: design D7 caps arrays at 30
    /// elements, which bounds the engine's shrink of the list, which tries
    /// leaving out each element in turn).
    static let wrapCount = 0...30
    /// The largest line index and position drawn (assumed: past both
    /// files' line count, `BuildOutputInterpreter.lineCap` each, and most
    /// lines' scalar count, so indices modulo them spread over all the
    /// lines and the whole line).
    static let positionBound = 200
    /// The share of wraps that go before a joining scalar when the line has
    /// one.
    static let joinerRate: Float = 0.5
    /// The share of wraps that write a joining scalar into the line first.
    static let writtenJoinerRate: Float = 0.33
    /// The share of wraps that write a backslash after their last sequence.
    static let backslashRate: Float = 0.25
    /// The backslash a wrap may write after its last sequence: text after
    /// a BEL, the end of a string terminator after `ESC`.
    static let backslash: Unicode.Scalar = "\\"
    /// Scalars that join any scalar but a control before them: combining
    /// marks, a zero-width joiner, an emoji modifier.
    static let joiningScalars: [Unicode.Scalar] = ["\u{301}", "\u{308}", "\u{200D}", "\u{1F3FD}"]
    /// A letter, which a joining scalar joins into one Character.
    static let letter = "m"
    /// The escape character, which no wrapped line held before.
    static let escapeByte = UInt8(ascii: "\u{1B}")
    /// A byte order mark, which the reader's UTF-8 decoding drops from the
    /// start of a line, and keeps after a sequence written before it.
    static let byteOrderMark: Unicode.Scalar = "\u{FEFF}"
    /// The replacement character, for an ill-formed UTF-8 sequence.
    static let replacementScalar: Unicode.Scalar = "\u{FFFD}"

    /// A wrap.
    static let wrap = zip(
        Gen<Int>.value(in: 0...positionBound),
        Pick.element(of: Kind.allCases),
        Gen<Int>.value(in: 0...positionBound),
        Gen<Int>.value(in: 0...positionBound),
        Gen.bool(joinerRate),
        Gen<Int>.value(in: joiningScalars.indices).optional(valueRate: writtenJoinerRate),
        Gen.bool(backslashRate)
    )
    .map { Wrap(line: $0, kind: $1, start: $2, end: $3, beforeJoiner: $4, joiner: $5, backslash: $6) }

    /// Generated output under the decided rules, and wraps for its lines.
    static let wrapped = zip(BuildOutputGen.output(.decided), wrap.array(of: wrapCount))
        .map { Wrapped(original: $0, wraps: $1) }

    /// `line` without and with `wrap`'s sequences written into its text,
    /// when it has a wrap, holds no escape and is UTF-8; otherwise as
    /// written, twice. UTF-8 is as the reader's Foundation decoding takes
    /// it; the scalars come from `scalars(of:)`, which keeps a byte order
    /// mark that starts the line, where that decoding drops it.
    static func wrapped(_ line: GeneratedBuildLine, by wrap: Wrap?) -> WrappedLine {
        let lineBreak = Data(line.lineBreak.utf8)
        guard let wrap, line.written.contains(escapeByte) == false,
              String(bytes: line.written, encoding: .utf8) != nil
        else {
            let data = Data(line.written) + lineBreak
            return WrappedLine(plain: data, data: data, isWrapped: false, isInsideCharacter: false, joins: false)
        }
        var scalars = scalars(of: line.written)
        let firstPlace = scalars.first == byteOrderMark ? 1 : 0
        var forced: Int?
        if let joiner = wrap.joiner {
            let offset = max(wrap.start % (scalars.count + 1), min(firstPlace, scalars.count))
            scalars.insert(joiningScalars[joiner], at: offset)
            forced = offset
        }
        let joiners = scalars.indices.filter { (letter + String(scalars[$0])).count == 1 }
        func place(_ position: Int) -> Int {
            let offset = wrap.beforeJoiner && joiners.isEmpty == false
                ? joiners[position % joiners.count]
                : position % (scalars.count + 1)
            return max(offset, firstPlace)
        }
        let inserts = inserts(of: wrap, scalarCount: scalars.count, first: forced, place: place)
        if wrap.backslash, wrap.kind != .truncated, let last = inserts.map(\.offset).max() {
            scalars.insert(backslash, at: last)
        }
        let plain = String(String.UnicodeScalarView(scalars))
        let inside = insidePlaces(of: plain)
        var written = String.UnicodeScalarView()
        for offset in 0...scalars.count {
            for insert in inserts where insert.offset == offset {
                written.append(contentsOf: insert.sequence.unicodeScalars)
            }
            if offset < scalars.count {
                written.append(scalars[offset])
            }
        }
        let joins = inserts.contains { insert in
            guard insert.offset < scalars.count, let last = insert.sequence.unicodeScalars.last else {
                return false
            }
            return (String(last) + String(scalars[insert.offset])).count == 1
        }
        return WrappedLine(
            plain: Data(plain.utf8) + lineBreak,
            data: Data(String(written).utf8) + lineBreak,
            isWrapped: true,
            isInsideCharacter: inserts.contains { inside.contains($0.offset) },
            joins: joins
        )
    }

    /// The Unicode scalars `bytes` encode in UTF-8, every one of them, a
    /// byte order mark at the start included; an ill-formed sequence reads
    /// as U+FFFD (none does in a line `wrapped(_:by:)` has checked).
    static func scalars(of bytes: [UInt8]) -> [Unicode.Scalar] {
        var codec = UTF8()
        var iterator = bytes.makeIterator()
        var scalars: [Unicode.Scalar] = []
        while true {
            switch codec.decode(&iterator) {
            case .scalarValue(let scalar):
                scalars.append(scalar)

            case .emptyInput:
                return scalars

            case .error:
                scalars.append(replacementScalar)
            }
        }
    }

    /// The sequences `wrap` writes into a line of `scalarCount` scalars, and
    /// the scalar offset each goes before (`scalarCount` for the end): the
    /// first at `first` when set, its positions otherwise mapped to offsets
    /// by `place`. A cut-off sequence goes at the end, where it can't
    /// swallow text.
    static func inserts(
        of wrap: Wrap,
        scalarCount: Int,
        first: Int?,
        place: (Int) -> Int
    ) -> [(offset: Int, sequence: String)] {
        let start = first ?? place(wrap.start)
        func span(open: String, close: String) -> [(offset: Int, sequence: String)] {
            [(start, open), (max(start, place(wrap.end)), close)]
        }
        return switch wrap.kind {
        case .csi:
            span(open: BuildLineDecoration.csiOpen, close: BuildLineDecoration.csiClose)

        case .oscBell:
            span(open: BuildLineDecoration.oscBellOpen, close: BuildLineDecoration.oscBellClose)

        case .oscTerminated:
            span(open: BuildLineDecoration.oscTerminatedOpen, close: BuildLineDecoration.oscTerminatedClose)

        case .truncated:
            [(scalarCount, BuildLineDecoration.truncations[wrap.start % BuildLineDecoration.truncations.count])]

        case .twoCharacter:
            [(start, BuildLineDecoration.twoCharacterEscape)]

        case .cursorStyle:
            [(start, BuildLineDecoration.cursorStyleEscape)]
        }
    }

    /// The scalar offsets inside `text`'s Characters: after a scalar that
    /// isn't the last of its Character.
    static func insidePlaces(of text: String) -> [Int] {
        var places: [Int] = []
        var offset = 0
        for character in text {
            let count = character.unicodeScalars.count
            places += (offset + 1)..<(offset + count)
            offset += count
        }
        return places
    }
}
