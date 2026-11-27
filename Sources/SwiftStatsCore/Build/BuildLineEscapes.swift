//
//  BuildLineEscapes.swift
//  SwiftStatsCore
//
//  Removes terminal escapes from a line of the T1 build's output (M7,
//  design §6.1). `--no-color-diagnostics` should leave none, but Swift 6.4
//  colours diagnostics and wraps group names in OSC-8 links when it isn't
//  passed, even into a pipe: ANSI CSI sequences (`ESC [ … final`), OSC
//  sequences (`ESC ] … BEL` or `ESC ] … ESC \`) and two-character escapes
//  are taken out before a line is read. Sequences are read on Unicode
//  scalars, not Characters: a combining mark just after a sequence's last
//  scalar joins it into one Character, but it isn't part of the sequence
//  and is kept (design B24, decided U13), as the checker reads code points.
//

/// Takes ANSI and OSC-8 escape sequences out of build output lines.
enum BuildLineEscapes {
    /// The escape character.
    private static let escape: Unicode.Scalar = "\u{1B}"
    /// The bell character, which ends an OSC sequence.
    private static let bell: Unicode.Scalar = "\u{07}"
    /// A CSI sequence's parameter and intermediate characters.
    private static let parameters: ClosedRange<Unicode.Scalar> = "\u{20}"..."\u{3F}"

    /// `text` without its escape sequences, and whether it held one.
    static func strip(_ text: String) -> (text: String, escaped: Bool) {
        let scalars = text.unicodeScalars
        guard scalars.contains(escape) else {
            return (text, false)
        }
        var kept = String.UnicodeScalarView()
        var index = scalars.startIndex
        while index < scalars.endIndex {
            let scalar = scalars[index]
            guard scalar == escape else {
                kept.append(scalar)
                index = scalars.index(after: index)
                continue
            }
            index = end(in: scalars, from: scalars.index(after: index))
        }
        return (String(kept), true)
    }

    /// Where the escape sequence whose escape character came just before
    /// `start` ends: after a CSI's final scalar, an OSC's bell or string
    /// terminator, or a two-character escape's second scalar.
    private static func end(in scalars: String.UnicodeScalarView, from start: String.Index) -> String.Index {
        guard start < scalars.endIndex else {
            return start
        }
        var index = scalars.index(after: start)
        switch scalars[start] {
        case "[":
            while index < scalars.endIndex, parameters.contains(scalars[index]) {
                index = scalars.index(after: index)
            }
            return index < scalars.endIndex ? scalars.index(after: index) : index

        case "]":
            while index < scalars.endIndex, scalars[index] != bell, scalars[index] != escape {
                index = scalars.index(after: index)
            }
            guard index < scalars.endIndex else {
                return index
            }
            let after = scalars.index(after: index)
            if scalars[index] == escape, after < scalars.endIndex, scalars[after] == "\\" {
                return scalars.index(after: after)
            }
            return scalars[index] == bell ? after : index

        default:
            return index
        }
    }
}
