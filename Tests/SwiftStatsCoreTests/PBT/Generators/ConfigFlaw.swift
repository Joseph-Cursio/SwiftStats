//
//  ConfigFlaw.swift
//  SwiftStatsCoreTests
//
//  One flaw put into a valid configuration for P11.1, whose only law for
//  a flawed text is that reading it returns or names a configuration
//  error, never traps: a value spelled oddly (out of its range, a YAML 1.1
//  integer, a special float, a tag, an anchor, a quoted number, and the
//  base-60 numbers whose places pass `Int`, design B30), a value of
//  another type, an `arguments` list that isn't `--skip <regex>` pairs (a
//  `--skip` last, an empty or flag-like regex, another flag), unknown or
//  repeated keys, a key that isn't plain text (a
//  tag, a sequence or mapping, a merge, an alias, an anchor), or one
//  section anchored and another its alias.
//

/// A flaw put into a valid configuration.
enum ConfigFlaw: Hashable, Sendable, CustomStringConvertible {
    /// The first top-level key's value anchored, the second's an alias of it.
    case aliased(anchored: String, alias: String)
    /// An `arguments` list at a path, holding these tokens.
    case arguments(path: [String], tokens: [String])
    /// A raw key put in at a level, at a position.
    case exoticKey(level: [String], key: String, position: Int)
    /// Unknown or repeated keys.
    case keyFault(KeyFault)
    /// The value at a path written as raw text.
    case spelling(path: [String], text: String)
    /// The value at a path replaced by a node of another type, or none.
    case wrongType(path: [String], value: YAMLDraft?)

    /// The anchor `aliased` names.
    static let anchorName = "a"

    /// The flaw, for a failure's report.
    var description: String {
        switch self {
        case let .aliased(anchored, alias):
            return "\(alias) an alias of \(anchored)"

        case let .arguments(path, tokens):
            return "\(path.joined(separator: ".")) given \(tokens)"

        case let .exoticKey(level, key, _):
            return "key \(key.debugDescription) at \(level)"

        case .keyFault(let fault):
            return fault.description

        case let .spelling(path, text):
            return "\(path.joined(separator: ".")) written \(text.debugDescription)"

        case let .wrongType(path, value):
            return "\(path.joined(separator: ".")) given \(value?.flowText ?? "no value")"
        }
    }

    /// `members` with the flaw put in.
    func applied(to members: [YAMLDraft.Member]) -> [YAMLDraft.Member] {
        switch self {
        case let .aliased(anchored, alias):
            let others = members.filter { $0.key.keyText != anchored && $0.key.keyText != alias }
            let value = members.last { $0.key.keyText == anchored }?.value?.flowText ?? "{}"
            return [YAMLDraft.member(anchored, .raw("&\(Self.anchorName) " + value))] + others
                + [YAMLDraft.member(alias, .raw("*" + Self.anchorName))]

        case let .arguments(path, tokens):
            return YAMLDraft.setting(.sequence(tokens.map(YAMLDraft.text)), at: path, in: members)

        case let .exoticKey(level, key, position):
            let member = YAMLDraft.Member(key: .raw(key), value: .text("1"))
            return YAMLDraft.inserting(member, at: position, under: level, in: members)

        case .keyFault(let fault):
            return fault.applied(to: members)

        case let .spelling(path, text):
            return YAMLDraft.setting(.raw(text), at: path, in: members)

        case let .wrongType(path, value):
            return YAMLDraft.setting(value, at: path, in: members)
        }
    }
}
