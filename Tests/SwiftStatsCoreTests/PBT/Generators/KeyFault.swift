//
//  KeyFault.swift
//  SwiftStatsCoreTests
//
//  Unknown or repeated keys put into a valid configuration at one level
//  (P11.3), and what the reader says of them, from PRD §10.1 ("other
//  unknown keys, at any level, ... are an error"), design §4.1.6 ("an
//  unknown key or a duplicate key is always refused, naming it") and the
//  reader's messages: unknown keys are named sorted, joined by commas, at
//  the top level bare, under a collector's entry or swiftmutator's
//  `options` by their full dotted path, elsewhere after "under `<level>`".
//  A key repeated with the same YAML type is refused by Yams as the text
//  is composed, naming it; a key YAML reads as two types (`1` plain, an
//  integer, and `"1"` quoted, a string) reaches the reader, which names a
//  top-level repeat as given more than once and, since no known key is
//  such a word, names a nested one as unknown. Keys are scalars only,
//  plain or quoted (assumed: a key that is tagged, or not text, is design
//  B31 and B32, awaiting U21; `ConfigGen+Cases` draws those for P11.1).
//

/// Unknown or repeated keys at one level of a configuration.
struct KeyFault: Hashable, Sendable, CustomStringConvertible {
    /// What the fault puts in.
    enum Kind: Hashable, Sendable {
        /// One key, written twice, first and second as quoted.
        case duplicate(key: String, first: YAMLDraft.Quote, second: YAMLDraft.Quote)
        /// Keys no level of PRD §10.1 knows, each a scalar.
        case unknown([YAMLDraft])
    }

    /// What reading the configuration gives.
    enum Expected: Hashable, Sendable {
        /// Yams' refusal of a repeated key, naming it.
        case duplicateInYAML(String)
        /// A configuration error with exactly this reason.
        case refused(String)
    }

    /// Key texts plain YAML reads as another type than a string, so the
    /// same text quoted is another key to Yams.
    static let typedKeys: Set<String> = ["1", "true"]

    /// The path of the mapping the keys go in; empty for the top level.
    let level: [String]
    /// What the fault puts in.
    let kind: Kind
    /// Where among that mapping's members the keys go.
    let position: Int

    /// The fault, for a failure's report.
    var description: String {
        switch kind {
        case let .duplicate(key, first, second):
            return "\(key.debugDescription) repeated, \(first) then \(second), at \(level)"

        case .unknown(let keys):
            return "unknown \(keys.map(\.flowText)) at \(level)"
        }
    }

    /// What reading a configuration holding the fault gives.
    var expected: Expected {
        switch kind {
        case let .duplicate(key, first, second):
            guard Self.typedKeys.contains(key), (first == .plain) != (second == .plain) else {
                return .duplicateInYAML(key)
            }
            guard level.isEmpty else {
                return .refused(Self.unknownReason([key], at: level))
            }
            return .refused("key(s) given more than once: \(key)")

        case .unknown(let keys):
            return .refused(Self.unknownReason(keys.compactMap(\.keyText), at: level))
        }
    }

    /// The reason naming `keys` as unknown at `level`.
    static func unknownReason(_ keys: [String], at level: [String]) -> String {
        let names = Set(keys).sorted()
        guard let first = level.first else {
            return "unknown key(s): " + names.joined(separator: ", ")
        }
        guard first == "collectors" else {
            return "unknown key(s) under `\(level.joined(separator: "."))`: " + names.joined(separator: ", ")
        }
        let prefix = level.joined(separator: ".") + "."
        return "unknown key(s): " + names.map { prefix + $0 }.joined(separator: ", ")
    }

    /// `members` with the fault put in: each unknown key, valued `1`, at
    /// `position` in the mapping at `level` (made if missing); or the
    /// repeated key's members there, every member already holding it
    /// removed first.
    func applied(to members: [YAMLDraft.Member]) -> [YAMLDraft.Member] {
        let value = YAMLDraft.text("1")
        switch kind {
        case let .duplicate(key, first, second):
            let cleared = YAMLDraft.removing(at: level + [key], in: members)
            let once = YAMLDraft.inserting(
                YAMLDraft.Member(key: .scalar(key, first), value: value),
                at: position,
                under: level,
                in: cleared
            )
            return YAMLDraft.inserting(
                YAMLDraft.Member(key: .scalar(key, second), value: value),
                at: position + 1,
                under: level,
                in: once
            )

        case .unknown(let keys):
            return keys.reduce(members) { edited, key in
                YAMLDraft.inserting(YAMLDraft.Member(key: key, value: value), at: position, under: level, in: edited)
            }
        }
    }
}
