//
//  ConfigLayout.swift
//  SwiftStatsCoreTests
//
//  How a configuration draft is laid out as text: from which depth on it
//  is written in flow style (0 writes the whole document so, a depth past
//  the deepest mapping writes it all in block style), what comes before
//  the first key (nothing, a document start, a comment, or a version
//  directive), and whether its lines end in `\r\n`.
//  None of these changes what the reader takes from the text.
//

/// How a draft is laid out as text.
struct ConfigLayout: Hashable, Sendable {
    /// The depth from which mappings and sequences are written in flow style.
    let flowDepth: Int
    /// What comes before the first key.
    let prefix: String
    /// Whether each line ends in `\r\n` rather than `\n`.
    let endsInCRLF: Bool

    /// `members` as a document laid out so.
    func text(of members: [YAMLDraft.Member]) -> String {
        let document = prefix + YAMLDraft.document(members, flowDepth: flowDepth)
        return endsInCRLF ? document.replacingOccurrences(of: "\n", with: "\r\n") : document
    }
}
