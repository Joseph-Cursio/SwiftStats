//
//  BuildOutputInterpreter.swift
//  SwiftStatsCoreTests
//
//  Turns one generated build-output file's decisions into its lines,
//  written and labelled, in three steps. Guard: a wild line, whose reading
//  isn't stated, gets a blank line on each side, so it can't join a
//  message or take the lines after it, and every stated line reads as if
//  it weren't there; a malformed timing line just after a header or plain
//  line, which the reader as built may take into a message (B10, fixed in
//  step 7), gets a blank line before it under the current rules and is
//  marked pending under the decided ones. Then the first `lineCap` lines
//  are kept (design D7). Write: each line takes its decoration's line
//  break, and each but a wild line its escape, an escape that would join
//  the Character after it moving to the line's end; an empty last line
//  always ends with a line break (unterminated, it isn't a line). Label:
//  by the rules `BuildOutputReader`'s doc comment states, over the lines'
//  kinds, which the generator knows by construction: a
//  timing line is an entry and a malformed or overlong one is counted
//  (standard error only); structure is skipped; a header takes the plain
//  lines after it, at most `continuationLimit`, up to the last after which
//  its text ends with an ID or a group (all of them when none does), and
//  reads its ID and group from that line; a macro header's origin is the
//  note right after what it took; a `warning: ` line is counted; anything
//  else is ignored. Nothing here calls the reader.
//

import Foundation
@testable import SwiftStatsCore

/// Writes and labels generated build-output files.
enum BuildOutputInterpreter {
    /// A header's message as read.
    struct Message {
        /// The diagnostic the header begins.
        let diagnostic: BuildDiagnostic
        /// How many lines after the header its message took.
        let consumed: Int
        /// What the header has, from how its message read.
        let traits: Set<BuildLineTrait>
    }

    /// The most lines a file has (assumed, design D7: room for a message
    /// that crosses the continuation limit, with lines around it).
    static let lineCap = 40
    /// The most lines a message takes after its header, as
    /// `BuildOutputReader`'s doc comment states ("at most 20"); stated
    /// here, not read from the reader, so a change there shows.
    static let continuationLimit = 20

    /// The lines `file` holds, written and labelled under `rules`; its
    /// timing lines are read only when `timings` (standard error).
    static func lines(of file: BuildFileDraft, rules: BuildOutputGen.Rules, timings: Bool) -> [GeneratedBuildLine] {
        let drafts = Array(guarded(file.blocks.flatMap(\.self), rules: rules).prefix(lineCap))
        let labels = label(drafts, timings: timings)
        return drafts.indices.map { index in
            let decoration = file.decorations.indices.contains(index) ? file.decorations[index] : .plain
            let unterminated = index == drafts.count - 1 && file.terminated == false
            return written(drafts[index], label: labels[index], decoration: decoration, unterminated: unterminated)
        }
    }

    /// The labels of `drafts`: what each reads as, and what a header has
    /// from how its message read.
    static func label(
        _ drafts: [BuildLineDraft],
        timings: Bool
    ) -> [(reading: BuildLineReading, traits: Set<BuildLineTrait>)] {
        var labels = drafts.map { (reading: reading(of: $0.shape, timings: timings), traits: Set<BuildLineTrait>()) }
        var index = 0
        while index < drafts.count {
            guard let message = message(at: index, in: drafts) else {
                index += 1
                continue
            }
            labels[index] = (.diagnostic(message.diagnostic), message.traits)
            for taken in (index + 1)..<(index + 1 + message.consumed) {
                labels[taken].reading = .continuation
            }
            index += 1 + message.consumed
        }
        return labels
    }

    /// The message of the header at `index`, read from the plain lines
    /// after it; nil when the line there isn't a header.
    static func message(at index: Int, in drafts: [BuildLineDraft]) -> Message? {
        guard case let .header(location, severity, first) = drafts[index].shape else {
            return nil
        }
        let run = drafts[(index + 1)...].prefix(while: \.shape.continuesMessage).compactMap { draft -> SuffixedText? in
            if case .plain(let text) = draft.shape {
                return text
            }
            return nil
        }
        let candidates = [first] + run.prefix(continuationLimit)
        let consumed = candidates.lastIndex(where: \.isComplete) ?? candidates.count - 1
        let taken = candidates[...consumed]
        let last = taken[consumed]
        var origin: BuildPlace?
        if case .macro = location, drafts.indices.contains(index + 1 + consumed),
           case .origin(let place) = drafts[index + 1 + consumed].shape {
            origin = place
        }
        let diagnostic = BuildDiagnostic(
            severity: severity,
            location: location,
            message: (taken.dropLast().map(\.rendered) + [last.readMessage]).joined(separator: "\n"),
            identifier: last.readIdentifier,
            group: last.readGroup,
            origin: origin
        )
        let traits = traits(of: diagnostic, taken: Array(taken), candidates: candidates.count, run: run.count)
        return Message(diagnostic: diagnostic, consumed: consumed, traits: traits)
    }

    /// What a line of `shape` reads as outside a message; a header's label
    /// is set from its message instead.
    private static func reading(of shape: BuildLineShape, timings: Bool) -> BuildLineReading {
        switch shape {
        case .blank, .origin, .structural:
            .skipped

        case .header, .plain, .stopper:
            .ignored

        case .malformedTiming, .overlongTiming:
            timings ? .unparsedTiming : .unstated

        case .otherWarning:
            .otherWarning

        case .timing(let entry):
            timings ? .entry(entry) : .unstated

        case .wild:
            .unstated
        }
    }

    /// What a header has, from its `diagnostic` and the `taken` lines of
    /// the `candidates` it could take, out of a `run` of plain lines.
    private static func traits(
        of diagnostic: BuildDiagnostic,
        taken: [SuffixedText],
        candidates: Int,
        run: Int
    ) -> Set<BuildLineTrait> {
        var traits: Set<BuildLineTrait> = []
        if run > continuationLimit {
            traits.insert(.crossesLimit)
        }
        if taken.count < candidates {
            traits.insert(.surplus)
        }
        if taken.dropLast().contains(where: \.isComplete) {
            traits.insert(.innerSuffix)
        }
        if diagnostic.identifier == nil, diagnostic.group == nil {
            traits.insert(.noSuffix)
        }
        if diagnostic.origin != nil {
            traits.insert(.macroOrigin)
        }
        if case .unknown = diagnostic.location {
            traits.insert(.unknownPlace)
        }
        return traits
    }

    /// `drafts` with blank lines around each wild line, and before each
    /// malformed timing line a message might take (current rules) or that
    /// line marked pending (decided rules).
    private static func guarded(_ drafts: [BuildLineDraft], rules: BuildOutputGen.Rules) -> [BuildLineDraft] {
        var guarded: [BuildLineDraft] = []
        for draft in drafts {
            switch draft.shape {
            case .wild:
                guarded += [.insertedBlank, draft, .insertedBlank]

            case .malformedTiming where mayContinue(guarded.last):
                guarded += rules == .current ? [.insertedBlank, draft] : [draft.adding(.pendingB10)]

            default:
                guarded.append(draft)
            }
        }
        return guarded
    }

    /// Whether a message may be open after `line`: it is a header or a
    /// plain line.
    private static func mayContinue(_ line: BuildLineDraft?) -> Bool {
        guard let line else {
            return false
        }
        if case .header = line.shape {
            return true
        }
        return line.shape.continuesMessage
    }

    /// `draft` written with `decoration`, labelled with `label`, with no
    /// line break when `unterminated` and not empty. A draft's own escape
    /// (the B24 block's, which only the decided rules generate) replaces the
    /// decoration's and stays where it joins the Character after it; a
    /// decoration's escape moves to the line's end instead. A wild line
    /// takes no escape, only its line break.
    private static func written(
        _ draft: BuildLineDraft,
        label: (reading: BuildLineReading, traits: Set<BuildLineTrait>),
        decoration: BuildLineDecoration,
        unterminated: Bool
    ) -> GeneratedBuildLine {
        var traits = draft.traits.union(label.traits)
        var bytes = draft.bytes
        if draft.shape != .wild {
            let escape = draft.escape ?? decoration.escape
            let written = BuildLineDecoration.written(draft.text, escape: escape, keepJoins: draft.escape != nil)
            bytes = written.bytes
            if escape != nil {
                traits.insert(.escaped)
            }
            if case .truncated = escape {
                traits.insert(.truncatedEscape)
            }
            if written.joinsKept {
                traits.insert(.pendingB24)
            }
        }
        var lineBreak = "\n"
        if unterminated, bytes.isEmpty == false {
            lineBreak = ""
            traits.insert(.unterminated)
        } else if decoration.carriageReturn, bytes.last != UInt8(ascii: "\r") {
            lineBreak = "\r\n"
            traits.insert(.carriageReturnLineFeed)
        }
        return GeneratedBuildLine(
            shape: draft.shape,
            text: draft.text,
            written: bytes,
            lineBreak: lineBreak,
            reading: label.reading,
            traits: traits
        )
    }
}
