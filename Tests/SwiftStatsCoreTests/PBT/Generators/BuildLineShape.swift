//
//  BuildLineShape.swift
//  SwiftStatsCoreTests
//
//  What kind of line the build-output generator wrote, which is all its
//  interpreter needs to say how the line reads (`BuildLineReading`): the
//  generator builds each line from its kind, so the kind is known by
//  construction, never parsed back. Only a plain line continues an open
//  diagnostic's message; every other kind ends it.
//

@testable import SwiftStatsCore

/// The kind of a generated build-output line, known by construction.
enum BuildLineShape: Hashable, Sendable {
    /// A blank line, or one of white space only.
    case blank
    /// A diagnostic's first line: where, how severe, and its message's
    /// first line.
    case header(location: BuildDiagnostic.Location, severity: BuildDiagnostic.Severity, message: SuffixedText)
    /// A line holding `ms<TAB>` that states no timing entry, its time
    /// otherwise within the digit bound or its fields wrong.
    case malformedTiming
    /// A macro expansion's origin note, naming `place`.
    case origin(BuildPlace)
    /// A line starting `warning: ` that is no diagnostic.
    case otherWarning
    /// A timing line but for a time with more whole digits than the bound.
    case overlongTiming
    /// Text that can continue a message, and is ignored anywhere else.
    case plain(SuffixedText)
    /// A line that ends a message and is otherwise ignored: a group's
    /// footnote, or one starting `info: `, `error: `, `note: ` or
    /// `remark: ` that is no diagnostic.
    case stopper
    /// A source excerpt, box or decorated line, which is skipped.
    case structural
    /// A timing line stating `entry`.
    case timing(TimingEntry)
    /// A line of arbitrary scalars or bytes, whose reading isn't stated.
    case wild

    /// Whether a line of this kind continues an open message.
    var continuesMessage: Bool {
        if case .plain = self {
            return true
        }
        return false
    }
}
