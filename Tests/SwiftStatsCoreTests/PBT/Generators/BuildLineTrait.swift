//
//  BuildLineTrait.swift
//  SwiftStatsCoreTests
//
//  What a generated build-output line has besides its kind, for the
//  generator's deterministic meta-test (design D14) to count, and for a
//  property to tally as antecedents. The `shapeB10`, `shapeB23` and
//  `shapeB24` traits mark the shapes the decided rules read differently
//  from the reader before step 7's fixes (B10's landed in step 7a with
//  B23's `ms<TAB>` half, the rest of B23's and B24's in step 7c), so the
//  reader now reads each as decided; only `BuildOutputGen.Rules.decided`
//  generates them.
//

/// A trait of a generated build-output line.
enum BuildLineTrait: String, CaseIterable, Hashable, Sendable {
    /// Written with CRLF.
    case carriageReturnLineFeed = "CRLF"
    /// A header whose plain lines run past the continuation limit.
    case crossesLimit = "crosses the continuation limit"
    /// A header whose place is a decoy `<path>:<line>:<column>: <severity>: `
    /// before the real one, read by the first-match rule.
    case decoyPlace = "decoy place"
    /// A timing line valid but for its empty declaration field, which only
    /// `BuildLineGrammar.timingEntry`'s own guard refuses.
    case emptyDeclaration = "empty declaration"
    /// Wrapped in escape sequences, or ending in a truncated one.
    case escaped
    /// A header whose message takes a line ending in a suffix before the
    /// line that ends it (M7 C2).
    case innerSuffix = "inner suffix"
    /// Inserted by the interpreter: a blank line around a wild line, or
    /// before a malformed timing line a message might take (current rules).
    case insertedBlank = "inserted blank"
    /// A wild line of bytes that aren't UTF-8.
    case invalidUTF8 = "invalid UTF-8"
    /// Holds a lone carriage return inside the line.
    case loneCarriageReturn = "lone CR"
    /// A header in a macro expansion whose origin note is read.
    case macroOrigin = "macro origin"
    /// A plain line that is a header but for one field.
    case nearHeader = "near header"
    /// A header whose message never completes with an ID or a group.
    case noSuffix = "no suffix"
    /// Holds a Prepend scalar where it joins no separator.
    case prepend
    /// Copied from a recorded build's output.
    case recorded
    /// B10: a malformed timing line just after a header or plain line,
    /// which the reader took into the message until B10's fix; it now
    /// ends the message, as the decided rules say.
    case shapeB10 = "B10 shape"
    /// B23: a Prepend scalar just before a place's `:` or a time's `ms`,
    /// read as decided since B23's fix (the `ms` half in step 7a, places
    /// in step 7c: the reader finds both on scalars).
    case shapeB23 = "B23 shape"
    /// B24: an escape whose last scalar joins the Character after it,
    /// read as decided since B24's fix (step 7c: escapes are read on
    /// scalars, so the Character's mark is kept).
    case shapeB24 = "B24 shape"
    /// A header whose message completes before the last plain line that
    /// could have continued it, so the lines after are ignored.
    case surplus
    /// Written with a truncated escape sequence at its end.
    case truncatedEscape = "truncated escape"
    /// A header at `<unknown>:<line>`.
    case unknownPlace = "unknown place"
    /// The last line of its file, with no line break after it.
    case unterminated
}
