//
//  DiagnosticText.swift
//  SwiftStatsCore
//
//  A diagnostic's whole message split from its suffixes (M7, design §6.1):
//  ` [<id>]`, which `-debug-diagnostic-names` appends, then ` [#<Group>]`
//  for a grouped diagnostic (`[shared_mutable_state_decl]
//  [#MutableGlobalVariable]`), read from the end of the joined text, on
//  Unicode scalars: a Prepend scalar just before a suffix's ` [` joins the
//  space into one Character, but it ends the message and the suffix is
//  still read (design B23, decided U13), as the checker reads code points.
//

/// A message, its diagnostic ID and its group.
struct DiagnosticText: Hashable, Sendable {
    /// The scalars a diagnostic ID is made of.
    private static let identifierScalars = Set("abcdefghijklmnopqrstuvwxyz0123456789_".unicodeScalars)
    /// What opens a group's suffix.
    private static let groupOpening = " [#".unicodeScalars
    /// What opens an ID's suffix.
    private static let identifierOpening = " [".unicodeScalars
    /// What closes a suffix.
    private static let closing: Unicode.Scalar = "]"

    /// The message without its suffixes or trailing white space.
    let message: String
    /// The diagnostic ID; nil when none ends the text.
    let identifier: String?
    /// The group; nil when none ends the text.
    let group: String?

    /// Whether the text ends with an ID or a group: a message can end
    /// there (it may still go on, when the suffix was a quoted source
    /// line's).
    var isComplete: Bool {
        identifier != nil || group != nil
    }

    /// `text` split: a trailing ` [#<letters and digits>]` is the group, a
    /// trailing ` [<lowercase letters, digits and _>]` before it the ID.
    init(_ text: String) {
        var rest = Substring(text).unicodeScalars
        while rest.last?.properties.isWhitespace == true {
            rest.removeLast()
        }
        var foundGroup: String?
        if let name = Self.suffix(of: rest, opening: Self.groupOpening),
           name.allSatisfy({ $0.isASCII && ($0.properties.isAlphabetic || $0.properties.numericType != nil) }) {
            foundGroup = String(Substring(name))
            rest = rest[..<name.startIndex].dropLast(Self.groupOpening.count)
        }
        var foundIdentifier: String?
        if let name = Self.suffix(of: rest, opening: Self.identifierOpening),
           name.allSatisfy(Self.identifierScalars.contains) {
            foundIdentifier = String(Substring(name))
            rest = rest[..<name.startIndex].dropLast(Self.identifierOpening.count)
        }
        message = String(Substring(rest))
        identifier = foundIdentifier
        group = foundGroup
    }

    /// The non-empty scalars between the last `opening` of `text` and the
    /// `]` that ends it; nil when it doesn't end so.
    private static func suffix(
        of text: Substring.UnicodeScalarView,
        opening: String.UnicodeScalarView
    ) -> Substring.UnicodeScalarView? {
        guard text.last == closing, let start = text.ranges(of: opening).last else {
            return nil
        }
        let name = text[start.upperBound..<text.index(before: text.endIndex)]
        return name.isEmpty ? nil : name
    }
}
