//
//  DiagnosticText.swift
//  SwiftStatsCore
//
//  A diagnostic's whole message split from its suffixes (M7, design §6.1):
//  ` [<id>]`, which `-debug-diagnostic-names` appends, then ` [#<Group>]`
//  for a grouped diagnostic (`[shared_mutable_state_decl]
//  [#MutableGlobalVariable]`), read from the end of the joined text.
//

/// A message, its diagnostic ID and its group.
struct DiagnosticText: Hashable, Sendable {
    /// The characters a diagnostic ID is made of.
    private static let identifierCharacters = Set("abcdefghijklmnopqrstuvwxyz0123456789_")

    /// The message without its suffixes or trailing white space.
    let message: String
    /// The diagnostic ID; nil when none ends the text.
    let identifier: String?
    /// The group; nil when none ends the text.
    let group: String?

    /// Whether the text ended with an ID or a group, so no line continues
    /// it.
    var isComplete: Bool {
        identifier != nil || group != nil
    }

    /// `text` split: a trailing ` [#<letters and digits>]` is the group, a
    /// trailing ` [<lowercase letters, digits and _>]` before it the ID.
    init(_ text: String) {
        var rest = Substring(text)
        while rest.last?.isWhitespace == true {
            rest.removeLast()
        }
        var foundGroup: String?
        if let name = Self.suffix(of: rest, opening: " [#"),
           name.allSatisfy({ $0.isASCII && ($0.isLetter || $0.isNumber) }) {
            foundGroup = String(name)
            rest = rest[..<name.startIndex].dropLast(" [#".count)
        }
        var foundIdentifier: String?
        if let name = Self.suffix(of: rest, opening: " ["), name.allSatisfy(Self.identifierCharacters.contains) {
            foundIdentifier = String(name)
            rest = rest[..<name.startIndex].dropLast(" [".count)
        }
        message = String(rest)
        identifier = foundIdentifier
        group = foundGroup
    }

    /// The non-empty text between the last `opening` of `text` and the `]`
    /// that ends it; nil when it doesn't end so.
    private static func suffix(of text: Substring, opening: String) -> Substring? {
        guard text.hasSuffix("]"), let start = text.range(of: opening, options: .backwards) else {
            return nil
        }
        let name = text[start.upperBound..<text.index(before: text.endIndex)]
        return name.isEmpty ? nil : name
    }
}
