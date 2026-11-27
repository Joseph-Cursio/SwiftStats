//
//  BuildLineDraft.swift
//  SwiftStatsCoreTests
//
//  One build-output line as a generator block built it, before the
//  interpreter decorates it with escapes and a line break and labels it:
//  its kind, the text it reads as once escapes are stripped, and its
//  bytes. A wild line of invalid UTF-8 has bytes no `String` holds; its
//  text is only for display. Every other line's text holds no line feed
//  and doesn't end in a carriage return, so any line can take CRLF.
//

import Foundation

/// A generated build-output line before decoration and labelling.
struct BuildLineDraft: Hashable, Sendable {
    /// The scalars whose presence makes a line hold a Prepend scalar.
    private static let prependScalars = Set(UnicodeGen.prepend.flatMap(\.unicodeScalars))
    /// A blank line the interpreter inserted.
    static let insertedBlank = Self(.blank, text: "", traits: [.insertedBlank])

    /// The kind of line.
    let shape: BuildLineShape
    /// What the line reads as once escapes are stripped.
    let text: String
    /// The line's bytes before escapes: `text` as UTF-8, or a wild line's
    /// own bytes.
    let bytes: [UInt8]
    /// What the line has besides its kind.
    let traits: Set<BuildLineTrait>
    /// An escape the block placed itself, which decorations don't replace;
    /// nil for most lines.
    let escape: BuildLineDecoration.Escape?

    /// A line of `shape` reading as `text`, with `traits` and those its
    /// text shows (a lone carriage return, a Prepend scalar).
    init(_ shape: BuildLineShape, text: String, traits: Set<BuildLineTrait>) {
        self.init(shape, text: text, traits: traits, escape: nil)
    }

    /// A line of `shape` reading as `text`, with `traits` and those its
    /// text shows, wrapped in `escape`.
    init(_ shape: BuildLineShape, text: String, traits: Set<BuildLineTrait>, escape: BuildLineDecoration.Escape?) {
        self.shape = shape
        self.text = text
        bytes = Array(text.utf8)
        var shown = traits
        if text.unicodeScalars.contains("\r") {
            shown.insert(.loneCarriageReturn)
        }
        if text.unicodeScalars.contains(where: Self.prependScalars.contains) {
            shown.insert(.prepend)
        }
        self.traits = shown
        self.escape = escape
    }

    /// A wild line of `bytes`, which need not be UTF-8.
    init(wildBytes bytes: [UInt8]) {
        shape = .wild
        text = String(bytes: bytes, encoding: .utf8) ?? String(bytes: bytes, encoding: .isoLatin1) ?? ""
        self.bytes = bytes
        traits = String(bytes: bytes, encoding: .utf8) == nil ? [.invalidUTF8] : []
        escape = nil
    }

    /// Every field given.
    private init(
        shape: BuildLineShape,
        text: String,
        bytes: [UInt8],
        traits: Set<BuildLineTrait>,
        escape: BuildLineDecoration.Escape?
    ) {
        self.shape = shape
        self.text = text
        self.bytes = bytes
        self.traits = traits
        self.escape = escape
    }

    /// This line with `trait` too.
    func adding(_ trait: BuildLineTrait) -> Self {
        Self(shape: shape, text: text, bytes: bytes, traits: traits.union([trait]), escape: escape)
    }
}
