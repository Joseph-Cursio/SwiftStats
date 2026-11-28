//
//  YAMLDraft+Text.swift
//  SwiftStatsCoreTests
//
//  A configuration draft written out as YAML. The document is a mapping
//  of top-level members; a mapping or sequence nested `flowDepth` levels
//  deep or deeper is written in flow style (`{a: 1, b: [x]}`), one above
//  it in block style, indented two spaces a level, with a sequence's
//  items each on its own `- ` line. A `flowDepth` of 0 writes the whole
//  document in flow style. An empty mapping or sequence, a key and a
//  sequence's item are always written inline, in flow style. A member
//  with no value is written `key:` in block style and `key: ~` in flow
//  style, both read as null. Scalars are written as `YAMLText` says.
//

/// Writing a draft as YAML.
extension YAMLDraft {
    /// The spaces each block level is indented by.
    static let indentWidth = 2

    /// The node written inline, in flow style.
    var flowText: String {
        switch self {
        case .mapping(let members):
            let pairs = members.map { member in member.key.flowText + ": " + (member.value?.flowText ?? "~") }
            return "{" + pairs.joined(separator: ", ") + "}"

        case .raw(let text):
            return text

        case let .scalar(text, quote):
            return Self.written(text, quote: quote)

        case .sequence(let items):
            return "[" + items.map(\.flowText).joined(separator: ", ") + "]"
        }
    }

    /// `members` as a document: block style above `flowDepth`, flow style
    /// from it, each line ending in a line feed.
    static func document(_ members: [Member], flowDepth: Int) -> String {
        guard flowDepth > 0 else {
            return mapping(members).flowText + "\n"
        }
        return block(members, level: 0, flowDepth: flowDepth)
    }

    /// The block lines of a mapping `level` levels deep holding `members`.
    static func block(_ members: [Member], level: Int, flowDepth: Int) -> String {
        let indent = String(repeating: " ", count: level * indentWidth)
        let isBlock = level + 1 < flowDepth
        return members
            .map { member in
                let key = indent + member.key.flowText + ":"
                switch member.value {
                case .none:
                    return key + "\n"

                case .mapping(let nested) where isBlock && nested.isEmpty == false:
                    return key + "\n" + block(nested, level: level + 1, flowDepth: flowDepth)

                case .sequence(let items) where isBlock && items.isEmpty == false:
                    let itemIndent = indent + String(repeating: " ", count: indentWidth)
                    return key + "\n" + items.map { itemIndent + "- " + $0.flowText + "\n" }.joined()

                case .some(let value):
                    return key + " " + value.flowText + "\n"
                }
            }
            .joined()
    }

    /// `text` written as `quote` says; single quotes fall back to double
    /// quotes when the text can't be single-quoted.
    static func written(_ text: String, quote: Quote) -> String {
        switch quote {
        case .double:
            return YAMLText.doubleQuoted(text)

        case .plain:
            return text

        case .single:
            return YAMLText.isSingleSafe(text) ? YAMLText.singleQuoted(text) : YAMLText.doubleQuoted(text)
        }
    }
}
