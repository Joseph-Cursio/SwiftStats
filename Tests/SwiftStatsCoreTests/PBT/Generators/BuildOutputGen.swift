//
//  BuildOutputGen.swift
//  SwiftStatsCoreTests
//
//  Build output for the properties of `BuildOutputReader` (design §3): a
//  standard error and a task log, each a list of blocks the interpreter
//  writes and labels line by line (`BuildOutputInterpreter`). Valid
//  blocks: timing lines (times within B1's twelve-digit bound, `<invalid
//  loc>` or a path with spaces, colons and non-ASCII text, a declaration
//  or none; a function body timed more than once at one place);
//  diagnostics in every place form, each severity, with an ID, a group,
//  both or neither, 0 to 25 continuation lines (so the limit of 20 is
//  crossed), a line ending ` [word]` before the real ID (M7 C2), a decoy
//  place read by the first-match rule, an origin note, excerpts;
//  structure, footnotes, `info:` and `warning: ` lines; real lines from
//  the recorded builds. Near-valid blocks: timing lines with one field
//  wrong (an empty declaration most often) or a time past the bound,
//  headers wrong in one field, a timing line without its tab; under the
//  decided rules, a diagnostic interrupted by a timing line (B10).
//  Unrecognised blocks: wild lines of any scalars or
//  of bytes that aren't UTF-8. Every line but a wild one may be wrapped
//  in escapes or end with a cut-off escape; a wild line takes only its
//  line break. Any line may end with CRLF, and the last may have no line
//  break. No line ends in a carriage return, so CR goes only before an LF
//  that has none. Words use letters that can't spell a severity, so a
//  line is a header only where a block wrote one. Files hold at most 40
//  lines and shrink by dropping blocks and decorations (D7).
//

import PropertyBased
@testable import SwiftStatsCore

/// Generators of build output, every line labelled with what it reads as.
enum BuildOutputGen {
    /// The rules the labels follow.
    enum Rules: Sendable {
        /// The reader as built before step 7's fixes: only shapes on which
        /// it and the decided rules agreed are generated, none of B10's,
        /// B23's or B24's. No property uses them since step 7c; the
        /// meta-test still pins what they draw.
        case current
        /// The rules U10 and U13 decided, which step 7's fixes (B10 in 7a,
        /// B23 and B24 in 7c) brought the reader to: the current shapes
        /// plus B10's, B23's and B24's, whose reading those fixes changed.
        case decided
    }

    /// Weight of timing lines among the standard error's blocks: most of a
    /// real standard error.
    static let timingWeight = 6.0
    /// Weight of diagnostics among a file's blocks.
    static let diagnosticWeight = 3.0
    /// Weight of the line kinds shared by both files.
    static let sharedWeight = 6.0
    /// Weight of each other kind of block.
    static let classWeight = 1.0
    /// Weight of a timing line valid but for its empty declaration, a block
    /// of its own: the near-valid line closest to a function body's, which
    /// only `BuildLineGrammar.timingEntry`'s own guard refuses. Drawn only
    /// as one of the malformed branch's eleven faults, it reached about one
    /// output in 36; this weight brings it to more than 0.3 per output
    /// (design D14, counted by the generator's meta-test), so P1.1's 100
    /// runs never miss it.
    static let emptyDeclarationWeight = 2.0
    /// Weight of a function body timed more than once, a block of its own:
    /// single timing lines rarely put two function bodies at one place, so
    /// the mapper's sums were reached in about one output in 30; this
    /// weight brings that past a quarter of outputs (design D14, counted
    /// by the generator's meta-test), so P1.1's 100 runs never miss it.
    static let repeatedBodyWeight = 2.0
    /// Weight of an interrupted diagnostic under the decided rules, a block
    /// of its own: a timing line right after a header or a line its message
    /// took came from single blocks in about one output in 12 for a refused
    /// line and one in 30 for a valid one; this weight brings both well
    /// past what design D14 needs for 100 runs (counted by the generators'
    /// meta-tests), so P1.2's runs, and P1.8's moves of a line that ended a
    /// message, never miss them.
    static let interruptedWeight = 3.0
    /// Weight of a macro diagnostic right before an origin note or a near
    /// miss, a block of its own: an origin note after a macro header came
    /// in about one output in 13, and its near misses in fewer; this weight
    /// brings the macro header before a near miss and before a padded note
    /// each past what design D14 needs for P1.5's runs (counted by the
    /// generator's meta-test).
    static let macroOriginWeight = 2.0
    /// Weight of a message with no ID ended by a blank line that isn't
    /// spaces only, a plain line after it, a block of its own: single
    /// blocks put such a blank right after an open message, before a
    /// plain line, in very few outputs; this weight brings it past what
    /// design D14 needs for P1.5's runs (counted by the generator's
    /// meta-test).
    static let blankEndedWeight = 2.0
    /// Weight of a near miss among the single lines: each near header is
    /// where one of the grammar's refusal rules shows (an empty path, a
    /// bare sigil, a white-space-led path among nine faults), and at the
    /// weight of the other kinds each fault came in about two outputs in a
    /// hundred.
    static let nearMissWeight = 3.0
    /// Weight of each of B10's, B23's and B24's shapes under the decided
    /// rules.
    static let fixedShapeWeight = 1.0
    /// Weight of one of those shapes under the current rules: never drawn.
    static let neverWeight = 0.0

    /// How many blocks the standard error has (assumed: with the
    /// multi-line blocks, enough to reach the line cap).
    static let errorBlocks = 0...10
    /// How many blocks the task log has (assumed, as above; diagnostics
    /// are all it is read for).
    static let logBlocks = 0...6
    /// How many decorations a file has: one per line, at most.
    static let decorationCount = 0...BuildOutputInterpreter.lineCap
    /// The largest escape position drawn (assumed: past most lines'
    /// length, so positions modulo the length spread over the whole line).
    static let positionBound = 200
    /// The largest echo index: one of the standard error's diagnostic
    /// blocks, modulo their count.
    static let echoBound = errorBlocks.upperBound

    /// The share of lines written with CRLF.
    static let carriageReturnRate: Float = 0.25
    /// The share of lines written with escapes.
    static let escapeRate: Float = 0.15
    /// The share of files whose last line ends with a line break.
    static let terminatedRate: Float = 0.8
    /// The share of outputs whose log repeats one of the standard error's
    /// diagnostics, which the reader keeps once.
    static let echoRate: Float = 0.3

    /// An escape position, taken modulo the line's length.
    static let position = Gen<Int>.value(in: 0...positionBound)

    /// The escapes a line can be wrapped in.
    static let escape = Gen.frequency(
        (classWeight, zip(position, position).map { BuildLineDecoration.Escape.csi(start: $0, end: $1) }),
        (classWeight, zip(position, position).map { BuildLineDecoration.Escape.oscBell(start: $0, end: $1) }),
        (classWeight, zip(position, position).map { BuildLineDecoration.Escape.oscTerminated(start: $0, end: $1) }),
        (classWeight, Pick.element(of: BuildLineDecoration.truncations).map(BuildLineDecoration.Escape.truncated)),
        (classWeight, position.map { BuildLineDecoration.Escape.twoCharacter($0) }),
        (classWeight, position.map { BuildLineDecoration.Escape.cursorStyle($0) })
    )

    /// One line's decoration.
    static let decoration = zip(Gen.bool(carriageReturnRate), escape.optional(valueRate: escapeRate))
        .map { BuildLineDecoration(carriageReturn: $0, escape: $1) }

    /// A generated build's output under `rules`.
    static func output(_ rules: Rules) -> Generator<GeneratedBuildOutput, AnySequence<Any>> {
        zip(
            file(errorBlock(rules), blocks: errorBlocks),
            file(logBlock(rules), blocks: logBlocks),
            Gen<Int>.value(in: 0...echoBound).optional(valueRate: echoRate)
        )
        .map { stderr, log, echo in
            GeneratedBuildOutput(rules: rules, stderr: stderr, log: echoed(log, from: stderr, at: echo))
        }
        .eraseToAny()
    }

    /// A file of `blocks` blocks drawn from `block`, with its decorations
    /// and final line break.
    static func file(
        _ block: Generator<[BuildLineDraft], AnySequence<Any>>,
        blocks: ClosedRange<Int>
    ) -> Generator<BuildFileDraft, AnySequence<Any>> {
        zip(block.array(of: blocks), decoration.array(of: decorationCount), Gen.bool(terminatedRate))
            .map { BuildFileDraft(blocks: $0, decorations: $1, terminated: $2) }
            .eraseToAny()
    }

    /// A block of the standard error: any block, timing lines included.
    static func errorBlock(_ rules: Rules) -> Generator<[BuildLineDraft], AnySequence<Any>> {
        Gen.frequency(
            (timingWeight, timing(rules).map { [$0] }),
            (classWeight, malformedTiming.map { [$0] }),
            (emptyDeclarationWeight, emptyDeclarationTiming.map { [$0] }),
            (repeatedBodyWeight, repeatedTiming),
            (classWeight, overlongTiming.map { [$0] }),
            (rules == .decided ? fixedShapeWeight : neverWeight, prependedTime.map { [$0] }),
            (diagnosticWeight, diagnostic(rules)),
            (macroOriginWeight, macroOrigin(rules)),
            (blankEndedWeight, blankEnded(rules)),
            (rules == .decided ? interruptedWeight : neverWeight, interruptedDiagnostic),
            (classWeight, recorded(timings: true)),
            (sharedWeight, line(rules).map { [$0] })
        )
        .eraseToAny()
    }

    /// A block of the task log: no timing lines, which it never holds.
    static func logBlock(_ rules: Rules) -> Generator<[BuildLineDraft], AnySequence<Any>> {
        Gen.frequency(
            (diagnosticWeight, diagnostic(rules)),
            (macroOriginWeight, macroOrigin(rules)),
            (blankEndedWeight, blankEnded(rules)),
            (classWeight, recorded(timings: false)),
            (sharedWeight, line(rules).map { [$0] })
        )
        .eraseToAny()
    }

    /// One line of a kind both files hold.
    static func line(_ rules: Rules) -> Generator<BuildLineDraft, AnySequence<Any>> {
        Gen.frequency(
            (classWeight, plain),
            (nearMissWeight, nearMiss),
            (classWeight, structural),
            (classWeight, stopper),
            (classWeight, otherWarning),
            (classWeight, blank),
            (classWeight, wild),
            (rules == .decided ? fixedShapeWeight : neverWeight, joinedEscape)
        )
        .eraseToAny()
    }

    /// `log` with the standard error's diagnostic block at `echo` (modulo
    /// their count) first, when `echo` is set and the standard error has
    /// one.
    static func echoed(_ log: BuildFileDraft, from stderr: BuildFileDraft, at echo: Int?) -> BuildFileDraft {
        let diagnostics = stderr.blocks.filter { block in
            if case .header = block.first?.shape {
                return true
            }
            return false
        }
        guard let echo, diagnostics.isEmpty == false else {
            return log
        }
        let blocks = [diagnostics[echo % diagnostics.count]] + log.blocks
        return BuildFileDraft(blocks: blocks, decorations: log.decorations, terminated: log.terminated)
    }
}
