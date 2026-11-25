//
//  BuildLineEscapes.swift
//  SwiftStatsCore
//
//  Removes terminal escapes from a line of the T1 build's output (M7,
//  design §6.1). `--no-color-diagnostics` should leave none, but Swift 6.4
//  colours diagnostics and wraps group names in OSC-8 links when it isn't
//  passed, even into a pipe: ANSI CSI sequences (`ESC [ … final`), OSC
//  sequences (`ESC ] … BEL` or `ESC ] … ESC \`) and two-character escapes
//  are taken out before a line is read.
//

/// Takes ANSI and OSC-8 escape sequences out of build output lines.
enum BuildLineEscapes {
    /// The escape character.
    private static let escape: Character = "\u{1B}"
    /// The bell character, which ends an OSC sequence.
    private static let bell: Character = "\u{07}"
    /// A CSI sequence's parameter and intermediate characters.
    private static let parameters: ClosedRange<Character> = "\u{20}"..."\u{3F}"

    /// `text` without its escape sequences, and whether it held one.
    static func strip(_ text: String) -> (text: String, escaped: Bool) {
        guard text.contains(escape) else {
            return (text, false)
        }
        var kept = ""
        var index = text.startIndex
        while index < text.endIndex {
            let character = text[index]
            guard character == escape else {
                kept.append(character)
                index = text.index(after: index)
                continue
            }
            index = end(in: text, from: text.index(after: index))
        }
        return (kept, true)
    }

    /// Where the escape sequence whose escape character came just before
    /// `start` ends: after a CSI's final character, an OSC's bell or string
    /// terminator, or a two-character escape's second character.
    private static func end(in text: String, from start: String.Index) -> String.Index {
        guard start < text.endIndex else {
            return start
        }
        var index = text.index(after: start)
        switch text[start] {
        case "[":
            while index < text.endIndex, parameters.contains(text[index]) {
                index = text.index(after: index)
            }
            return index < text.endIndex ? text.index(after: index) : index

        case "]":
            while index < text.endIndex, text[index] != bell, text[index] != escape {
                index = text.index(after: index)
            }
            guard index < text.endIndex else {
                return index
            }
            let after = text.index(after: index)
            if text[index] == escape, after < text.endIndex, text[after] == "\\" {
                return text.index(after: after)
            }
            return text[index] == bell ? after : index

        default:
            return index
        }
    }
}
