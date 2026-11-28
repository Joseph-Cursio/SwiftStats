//
//  HintDraft.swift
//  SwiftStatsCoreTests
//
//  An outskirts hint as decisions, for P9.4: what comes before the
//  opening parenthesis, whether there is one, the text, and whether a
//  closing parenthesis ends it. A hint drafted as `name(text)` with a name
//  of ASCII letters should split back into that name and text, whatever
//  the text holds (parentheses, a combining mark first, a Prepend scalar
//  last); any other hint should read as `HintPattern`, the reference, says.
//

/// An outskirts hint as decisions.
struct HintDraft: Hashable, Sendable {
    /// What comes before the opening parenthesis.
    let name: String
    /// Whether an opening parenthesis follows the name.
    let opens: Bool
    /// The text after it.
    let text: String
    /// Whether a closing parenthesis ends the hint.
    let closes: Bool

    /// The hint as text.
    var rendered: String {
        name + (opens ? "(" : "") + text + (closes ? ")" : "")
    }

    /// Whether it is drafted as `name(text)` with a name of ASCII letters.
    var isWrittenSplit: Bool {
        opens && closes && name.isEmpty == false && name.unicodeScalars.allSatisfy(HintPattern.isASCIILetter)
    }

    /// The name and text it should read as: the drafted ones when it is
    /// drafted as `name(text)` with a name of ASCII letters (a round trip),
    /// else `HintPattern`'s reading.
    var expected: (name: String, text: String?) {
        isWrittenSplit ? (name, text) : HintPattern.split(rendered)
    }
}
