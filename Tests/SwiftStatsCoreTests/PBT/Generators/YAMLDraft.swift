//
//  YAMLDraft.swift
//  SwiftStatsCoreTests
//
//  A YAML node as the configuration generators build it (design §4.1.6):
//  a scalar written plain or quoted, a sequence, a mapping of members in
//  order, or raw text written exactly as given (a tag, an anchor or an
//  alias before a value, or a key that isn't text). `YAMLDraft+Text`
//  writes a draft out, in block style above a depth and in flow style
//  from it; `YAMLDraft+Edits` sets, removes and adds members at a path of
//  key texts. Writing YAML by hand, rather than through Yams' emitter,
//  keeps the library the reader parses with out of the inputs it is
//  tested on.
//

/// A YAML node, as a draft writes it.
indirect enum YAMLDraft: Hashable, Sendable {
    /// A mapping's members, in order.
    case mapping([Member])
    /// Text written exactly as given.
    case raw(String)
    /// A scalar's text and how it is written.
    case scalar(String, Quote)
    /// A sequence's items, in order.
    case sequence([Self])

    /// One member of a mapping.
    struct Member: Hashable, Sendable {
        /// Its key.
        let key: YAMLDraft
        /// Its value; nil for none, which YAML reads as null.
        let value: YAMLDraft?
    }

    /// How a scalar is written.
    enum Quote: Hashable, Sendable {
        /// Between double quotes, escaped where YAML requires.
        case double
        /// As it is: the draft's builder makes sure YAML reads it back.
        case plain
        /// Between single quotes, a quote doubled.
        case single
    }

    /// The text of a scalar key, however it is quoted; nil for any other
    /// node. The reader names keys by this text.
    var keyText: String? {
        guard case let .scalar(text, _) = self else {
            return nil
        }
        return text
    }

    /// `text` as a scalar: plain when YAML reads it back plain as the same
    /// text in any context, else double-quoted. A text a plain scalar
    /// would read as another type (`1`, `true`, `~`) stays plain: the
    /// reader takes most values' text whatever their type.
    static func text(_ text: String) -> Self {
        .scalar(text, YAMLText.isPlainSafe(text) ? .plain : .double)
    }

    /// A member whose key is `key`, written as `text(_:)` writes it, and
    /// whose value is `value`.
    static func member(_ key: String, _ value: Self?) -> Member {
        Member(key: text(key), value: value)
    }
}
