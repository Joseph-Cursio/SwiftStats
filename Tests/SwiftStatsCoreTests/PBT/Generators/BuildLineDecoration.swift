//
//  BuildLineDecoration.swift
//  SwiftStatsCoreTests
//
//  How a generated build-output line is written around its text: CRLF or
//  LF, and escape sequences Swift prints when colours aren't turned off
//  (a CSI colour pair, a CSI with an intermediate byte, an OSC-8 link
//  ended by `ESC \` or by BEL, a two-character escape, or a sequence cut
//  off at the end of the line, an OSC cut just after its terminator's
//  escape among them).
//  Escapes go only into lines without one, at Character boundaries, and
//  `BuildLineEscapes.strip` takes each out whole, so the line still reads
//  as its text. One shape was B24's (U13, fixed in step 7c): when an
//  escape's last scalar joins the Character after it, the reader before
//  the fix took that Character into the escape. A decoration's escape
//  never stays there: it moves to the end of the line. Only the B24 block,
//  which the decided rules alone generate, keeps such an escape in place,
//  marked.
//  Positions are drawn as numbers and taken modulo the line's length, so
//  any decoration fits any line.
//

/// The line break and escapes a generated build-output line is written
/// with.
struct BuildLineDecoration: Hashable, Sendable {
    /// Escape sequences around part of a line.
    enum Escape: Hashable, Sendable {
        /// A CSI colour, opened before the Character at `start` and reset
        /// before the one at `end`.
        case csi(start: Int, end: Int)
        /// A CSI with an intermediate byte (a cursor style) before the
        /// Character at the position.
        case cursorStyle(Int)
        /// An OSC-8 link ended by BEL, around the same span.
        case oscBell(start: Int, end: Int)
        /// An OSC-8 link ended by `ESC \`, around the same span.
        case oscTerminated(start: Int, end: Int)
        /// A sequence cut off at the end of the line.
        case truncated(String)
        /// A two-character escape before the Character at the position.
        case twoCharacter(Int)
    }

    /// A line written as is, with LF.
    static let plain = Self(carriageReturn: false, escape: nil)

    /// What opens a CSI colour.
    static let csiOpen = "\u{1B}[1;33m"
    /// What resets it.
    static let csiClose = "\u{1B}[0m"
    /// What opens an OSC-8 link ended by BEL.
    static let oscBellOpen = "\u{1B}]8;;https://swift.org\u{07}"
    /// What closes it.
    static let oscBellClose = "\u{1B}]8;;\u{07}"
    /// What opens an OSC-8 link ended by `ESC \`.
    static let oscTerminatedOpen = "\u{1B}]8;;https://docs.swift.org/compiler/documentation/diagnostics\u{1B}\\"
    /// What closes it.
    static let oscTerminatedClose = "\u{1B}]8;;\u{1B}\\"
    /// A two-character escape (save cursor).
    static let twoCharacterEscape = "\u{1B}7"
    /// A CSI with a parameter, an intermediate byte (a space, 0x20 to 0x2F
    /// being a CSI's intermediates) and its final: the cursor's style.
    static let cursorStyleEscape = "\u{1B}[2 q"
    /// The sequences a line can end in, cut off: a bare escape, a CSI with
    /// no final, part of one, an OSC with no terminator, and one cut just
    /// after its string terminator's escape, the line's last scalar.
    static let truncations = [
        "\u{1B}", "\u{1B}[", "\u{1B}[1;3", "\u{1B}]8;;https://swift.org", "\u{1B}]8;;https://swift.org\u{1B}"
    ]

    /// Whether the line ends with CRLF rather than LF.
    let carriageReturn: Bool
    /// The escapes written into the line; nil for none.
    let escape: Escape?

    /// `text` written with `escape`, and whether an escape stayed where its
    /// last scalar joins the Character after it (`joinsKept`, B24): it
    /// stays only when `keepJoins`, and otherwise moves to the line's end.
    static func written(
        _ text: String,
        escape: Escape?,
        keepJoins: Bool
    ) -> (bytes: [UInt8], joinsKept: Bool) {
        guard let escape else {
            return (Array(text.utf8), false)
        }
        let characters = Array(text)
        var joined = false
        func placed(_ position: Int, after sequence: String) -> Int {
            let index = position % (characters.count + 1)
            guard index < characters.count, (sequence + String(characters[index])).count <= sequence.count else {
                return index
            }
            joined = true
            return keepJoins ? index : characters.count
        }
        func span(_ start: Int, _ end: Int, open: String, close: String) -> [(index: Int, sequence: String)] {
            let first = placed(start, after: open)
            return [(first, open), (max(first, placed(end, after: close)), close)]
        }
        let inserts: [(index: Int, sequence: String)] = switch escape {
        case let .csi(start, end):
            span(start, end, open: csiOpen, close: csiClose)

        case let .oscBell(start, end):
            span(start, end, open: oscBellOpen, close: oscBellClose)

        case let .oscTerminated(start, end):
            span(start, end, open: oscTerminatedOpen, close: oscTerminatedClose)

        case .truncated(let sequence):
            [(characters.count, sequence)]

        case .twoCharacter(let position):
            [(placed(position, after: twoCharacterEscape), twoCharacterEscape)]

        case .cursorStyle(let position):
            [(placed(position, after: cursorStyleEscape), cursorStyleEscape)]
        }
        var written = ""
        for (index, character) in characters.enumerated() {
            written += inserts.filter { $0.index == index }.map(\.sequence).joined()
            written.append(character)
        }
        written += inserts.filter { $0.index == characters.count }.map(\.sequence).joined()
        return (Array(written.utf8), joined && keepJoins)
    }
}
