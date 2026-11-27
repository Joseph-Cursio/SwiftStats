//
//  SuffixedText.swift
//  SwiftStatsCoreTests
//
//  A line of a generated diagnostic's message, as the generator built it:
//  a body that ends in a word, then an ID part and a group part, each
//  absent, well formed or malformed. How it reads is stated from
//  `DiagnosticText`'s doc comment, not by calling it: a trailing
//  ` [#<letters and digits>]` is the group, a trailing ` [<lowercase
//  letters, digits and _>]` before it the ID. A malformed group ends the
//  text with `]` that no suffix reads, so nothing is taken off; a
//  malformed ID stays in the message. The body never ends in white space
//  or `]`, so only the parts the generator chose can read as suffixes.
//

/// A message line's body and its ID and group parts.
struct SuffixedText: Hashable, Sendable {
    /// One suffix part.
    enum Part: Hashable, Sendable {
        /// No part.
        case absent
        /// A malformed part, its full text (` [Bad]`, ` [#Bad-Group]`):
        /// it reads as part of the message.
        case malformed(String)
        /// A well-formed part, its name (`pbd_never_used`, `NoUsage`).
        case valid(String)
    }

    /// What opens an ID part.
    static let identifierOpening = " ["
    /// What opens a group part.
    static let groupOpening = " [#"
    /// What closes either part.
    static let closing = "]"

    /// The body, which ends in a word.
    let body: String
    /// The ID part.
    let identifier: Part
    /// The group part, after the ID part.
    let group: Part

    /// The text as written: body, ID part, group part.
    var rendered: String {
        body + Self.render(identifier, opening: Self.identifierOpening) + Self.render(group, opening: Self.groupOpening)
    }

    /// The group the text ends with, when its group part is well formed.
    var readGroup: String? {
        if case .valid(let name) = group {
            return name
        }
        return nil
    }

    /// The ID the text ends with: a well-formed ID part, unless a malformed
    /// group part ends the text after it.
    var readIdentifier: String? {
        if case .malformed = group {
            return nil
        }
        if case .valid(let name) = identifier {
            return name
        }
        return nil
    }

    /// The text without the parts that read as suffixes.
    var readMessage: String {
        let identifierText = readIdentifier == nil ? Self.render(identifier, opening: Self.identifierOpening) : ""
        let groupText = readGroup == nil ? Self.render(group, opening: Self.groupOpening) : ""
        return body + identifierText + groupText
    }

    /// Whether the text ends with an ID or a group, where a message can end.
    var isComplete: Bool {
        readIdentifier != nil || readGroup != nil
    }

    /// `body` with no suffix parts.
    init(_ body: String) {
        self.init(body: body, identifier: .absent, group: .absent)
    }

    /// `body` followed by its `identifier` and `group` parts.
    init(body: String, identifier: Part, group: Part) {
        self.body = body
        self.identifier = identifier
        self.group = group
    }

    /// The text of `part`, opened by `opening` when well formed.
    private static func render(_ part: Part, opening: String) -> String {
        switch part {
        case .absent:
            ""

        case .malformed(let text):
            text

        case .valid(let name):
            opening + name + closing
        }
    }
}
