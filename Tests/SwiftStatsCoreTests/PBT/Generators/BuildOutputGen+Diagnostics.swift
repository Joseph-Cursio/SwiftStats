//
//  BuildOutputGen+Diagnostics.swift
//  SwiftStatsCoreTests
//
//  Diagnostic blocks: a header, continuation lines, maybe an origin note,
//  maybe excerpts. A header is `<place>: <severity>: <message>`; with a
//  decoy, a file's place and a severity come first, so by the first-match
//  rule the decoy is the place and the rest of the line is the message.
//  Continuations come short (0 to 3), long (18 to 25, so the limit of 20
//  is crossed) or long without a suffix until an ID on a line past the
//  limit, which the message never reaches. A header's message is sometimes
//  empty: the line ends at `<severity>:`. An origin note follows any
//  header; only a macro header's message reads it, and only when the note
//  comes right after the lines the message took. Its text may end in
//  spaces, a tab or a no-break space, which are trimmed; a near miss, a
//  decorated line with the origin text and another severity or a trailing
//  form feed, names no origin. A block of its own puts a macro header
//  right before one of these. Another ends a message with no ID at a blank
//  line that isn't spaces only, a plain line after it. Under the decided rules a
//  diagnostic may also be interrupted: a header with no ID, up to two plain
//  lines, a timing line, valid or one the grammar refuses (B10: either ends
//  the message, and a refused one on the standard error is counted), and
//  maybe a plain line with an ID, which the message would have reached had
//  the timing line continued it.
//

import PropertyBased
@testable import SwiftStatsCore

extension BuildOutputGen {
    /// Weight of short continuation runs: most diagnostics have none, and a
    /// long run costs twenty lines to generate.
    static let shortRunWeight = 12.0
    /// The share of headers with a decoy place.
    static let decoyRate: Float = 0.1
    /// The share of diagnostic blocks with an origin note.
    static let originRate: Float = 0.3
    /// How many continuation lines a short run has (assumed).
    static let shortRun = 0...3
    /// How many continuation lines a long run has (forced: either side of
    /// the limit of 20; the top assumed).
    static let longRun = 18...25
    /// How many unsuffixed lines come before the ID of a run whose ID the
    /// message never reaches (forced: at least the limit).
    static let unsuffixedRun = BuildOutputInterpreter.continuationLimit...24
    /// How many excerpt lines follow a diagnostic (assumed).
    static let excerptCount = 0...2
    /// How many plain lines an interrupted message takes before the refused
    /// timing line (assumed: none, and enough for a run).
    static let interruptedRun = 0...2
    /// The share of interrupted diagnostics with a plain line ending in an
    /// ID after the refused timing line.
    static let resumedRate: Float = 0.5
    /// The share of headers whose message is empty.
    static let emptyMessageRate: Float = 0.1
    /// Weight of an origin note written exactly.
    static let exactOriginWeight = 3.0

    /// The severities, the most common first.
    static let severities: [BuildDiagnostic.Severity] = [.warning, .error, .note, .remark]
    /// How an origin note's line is decorated.
    static let originDecorations = ["`- ", "   `- ", "|- "]
    /// The text of the note that names a macro expansion's origin, as
    /// `BuildLineGrammar`'s doc comment states it.
    static let originNote = "expanded code originates here"
    /// What an origin note's text may end in, trimmed before it is matched
    /// (Foundation's whitespaces: spaces and tabs).
    static let originTrailings = [" ", "  ", "\t", "\u{A0}"]
    /// The severities a near-miss origin line has instead of `note`.
    static let otherSeverities: [BuildDiagnostic.Severity] = [.warning, .error, .remark]
    /// What a near-miss origin line's text ends in that isn't trimmed: a
    /// form feed.
    static let untrimmedEnding = "\u{C}"

    /// A continuation line.
    static let continuation = continuationText.map { BuildLineDraft(.plain($0), text: $0.rendered, traits: []) }

    /// A continuation line with no suffix part.
    static let unsuffixedContinuation = zip(Pick.element(of: indentations), text)
        .map { indentation, body in
            let line = SuffixedText(indentation + body)
            return BuildLineDraft(.plain(line), text: line.rendered, traits: [])
        }

    /// A continuation line ending with a well-formed ID.
    static let identifiedContinuation = zip(text, Pick.element(of: identifiers))
        .map { body, identifier in
            let line = SuffixedText(body: body, identifier: .valid(identifier), group: .absent)
            return BuildLineDraft(.plain(line), text: line.rendered, traits: [])
        }

    /// A run of continuation lines: short, long, or long with its ID past
    /// the limit.
    static let continuations = Gen.frequency(
        (shortRunWeight, continuation.array(of: shortRun)),
        (classWeight, continuation.array(of: longRun)),
        (classWeight, zip(unsuffixedContinuation.array(of: unsuffixedRun), identifiedContinuation).map { $0 + [$1] })
    )

    /// A timing line the grammar refuses, which ends any message: one with
    /// a fault, one valid but for its empty declaration, one with a time
    /// past the bound, or one with a Prepend scalar before its `ms`.
    static let refusedTiming = Gen.frequency(
        (classWeight, malformedTiming),
        (classWeight, emptyDeclarationTiming),
        (classWeight, overlongTiming),
        (classWeight, prependedTime)
    )

    /// An interrupted diagnostic (B10, decided U10; drawn only under the
    /// decided rules): a header whose message has no ID or group, up to two
    /// plain lines with none, a timing line, refused or valid, which ends
    /// the message, and maybe a plain line ending in an ID, which the
    /// message would have taken (and its ID) had the timing line continued
    /// it.
    static let interruptedDiagnostic = zip(
        zip(headerPlace(.decided), Pick.element(of: severities), text),
        unsuffixedContinuation.array(of: interruptedRun),
        Gen.frequency((classWeight, refusedTiming), (classWeight, timing(.decided))),
        identifiedContinuation.optional(valueRate: resumedRate)
    )
    .map { header, run, interruption, resumed in
        let (place, severity, body) = header
        let message = SuffixedText(body)
        let first = BuildLineDraft(
            .header(location: place.location, severity: severity, message: message),
            text: "\(place.text): \(severity.rawValue): \(message.rendered)",
            traits: place.traits
        )
        return [first] + run + [interruption] + [resumed].compactMap(\.self)
    }

    /// Whether a timing line the grammar refuses comes, in `lines`, right
    /// after a header or a line its message took: a message is open there,
    /// and the line must end it (B10), the antecedent P1.2's message law
    /// needs.
    static func refusesInMessage(_ lines: [GeneratedBuildLine]) -> Bool {
        zip(lines, lines.dropFirst()).contains { before, line in
            [.malformedTiming, .overlongTiming].contains(line.shape) && opensMessage(before.reading)
        }
    }

    /// Whether a diagnostic with no ID or group takes a line, in `lines`:
    /// the reading U10 kept (design B8), the antecedent P1.5 needs for it.
    static func takesUnidentified(_ lines: [GeneratedBuildLine]) -> Bool {
        zip(lines, lines.dropFirst()).contains { header, next in
            guard case .diagnostic(let diagnostic) = header.reading, next.reading == .continuation else {
                return false
            }
            return diagnostic.identifier == nil && diagnostic.group == nil
        }
    }

    /// Whether a line reading as `reading` leaves a message open after it:
    /// a header, or a line a message took.
    static func opensMessage(_ reading: BuildLineReading) -> Bool {
        switch reading {
        case .continuation, .diagnostic:
            true

        default:
            false
        }
    }

    /// A diagnostic block under `rules`.
    static func diagnostic(_ rules: Rules) -> Generator<[BuildLineDraft], AnySequence<Any>> {
        zip(
            header(rules),
            continuations,
            origin(rules).optional(valueRate: originRate),
            structural.array(of: excerptCount)
        )
        .map { header, continuations, origin, excerpts in
            [header] + continuations + [origin].compactMap(\.self) + excerpts
        }
        .eraseToAny()
    }

    /// A diagnostic's first line under `rules`: its message sometimes
    /// empty, the line ending at `<severity>:` (`emptyMessage`).
    static func header(_ rules: Rules) -> Generator<BuildLineDraft, AnySequence<Any>> {
        zip(
            headerPlace(rules),
            Pick.element(of: severities),
            headerMessage,
            zip(filePlace(.current), Pick.element(of: severities)).optional(valueRate: decoyRate),
            Gen.bool(emptyMessageRate)
        )
        .map { place, severity, message, decoy, empty in
            guard empty else {
                return headerLine(place: place, severity: severity, message: message, decoy: decoy)
            }
            return BuildLineDraft(
                .header(location: place.location, severity: severity, message: SuffixedText("")),
                text: "\(place.text): \(severity.rawValue):",
                traits: place.traits.union([.emptyMessage])
            )
        }
        .eraseToAny()
    }

    /// A macro expansion's origin note under `rules`: written exactly, or
    /// ending in white space that is trimmed (`paddedOrigin`); or a near
    /// miss, a decorated line that names no origin (`nearOrigin`): another
    /// severity, or a form feed after the text.
    static func origin(_ rules: Rules) -> Generator<BuildLineDraft, AnySequence<Any>> {
        Gen.frequency(
            (exactOriginWeight, zip(Pick.element(of: originDecorations), filePlace(rules)).map { decoration, place in
                let text = "\(decoration)\(place.text): note: \(originNote)"
                return BuildLineDraft(.origin(place.place), text: text, traits: place.traits)
            }),
            (classWeight, zip(Pick.element(of: originDecorations), filePlace(rules), Pick.element(of: originTrailings))
                .map { decoration, place, padding in
                    let text = "\(decoration)\(place.text): note: \(originNote)\(padding)"
                    return BuildLineDraft(.origin(place.place), text: text, traits: place.traits.union([.paddedOrigin]))
                }),
            (classWeight, zip(Pick.element(of: originDecorations), filePlace(rules), Pick.element(of: otherSeverities))
                .map { decoration, place, severity in
                    let text = "\(decoration)\(place.text): \(severity.rawValue): \(originNote)"
                    return BuildLineDraft(.structural, text: text, traits: place.traits.union([.nearOrigin]))
                }),
            (classWeight, zip(Pick.element(of: originDecorations), filePlace(rules)).map { decoration, place in
                let text = "\(decoration)\(place.text): note: \(originNote)\(untrimmedEnding)"
                return BuildLineDraft(.structural, text: text, traits: place.traits.union([.nearOrigin]))
            })
        )
        .eraseToAny()
    }

    /// A macro diagnostic right before an origin note or a near miss (a
    /// block of its own, so P1.5 meets both often): its message takes no
    /// line, as the decorated line after it can't continue one.
    static func macroOrigin(_ rules: Rules) -> Generator<[BuildLineDraft], AnySequence<Any>> {
        zip(Pick.element(of: macroNames), number, number, Pick.element(of: severities), headerMessage, origin(rules))
            .map { name, line, column, severity, message, origin in
                let place = macroPlace(name: name, line: line, column: column)
                return [headerLine(place: place, severity: severity, message: message, decoy: nil), origin]
            }
            .eraseToAny()
    }

    /// A diagnostic whose message has no ID or group, a blank line that
    /// isn't spaces only (a tab, a no-break or an ideographic space), and
    /// a plain line, which the blank line keeps out of the message (a
    /// block of its own, so P1.5 meets it often).
    static func blankEnded(_ rules: Rules) -> Generator<[BuildLineDraft], AnySequence<Any>> {
        zip(headerPlace(rules), Pick.element(of: severities), text, Pick.element(of: otherBlanks), continuation)
            .map { place, severity, body, blank, after in
                [
                    headerLine(place: place, severity: severity, message: SuffixedText(body), decoy: nil),
                    BuildLineDraft(.blank, text: blank, traits: []),
                    after
                ]
            }
            .eraseToAny()
    }

    /// Whether, in `lines`, a blank line that isn't spaces only comes right
    /// after a header or a line its message took, a plain line after it:
    /// the blank line ends the message, the antecedent P1.5 needs for it.
    static func endsAtOtherBlank(_ lines: [GeneratedBuildLine]) -> Bool {
        lines.indices.dropFirst().dropLast().contains { index in
            let blank = lines[index]
            return blank.shape == .blank && blank.text.contains { $0 != " " }
                && opensMessage(lines[index - 1].reading) && lines[index + 1].shape.continuesMessage
        }
    }

    /// Whether, in `lines`, a header or a line its message took holds a bar
    /// with text before it: no excerpt, as the reader must read it.
    static func barInMessage(_ lines: [GeneratedBuildLine]) -> Bool {
        lines.contains { opensMessage($0.reading) && $0.text.contains("|") }
    }

    /// Whether, in `lines`, a message took a line led by digits that aren't
    /// ASCII and a bar: no excerpt's gutter, as the reader must read it.
    static func takesNonASCIIGutter(_ lines: [GeneratedBuildLine]) -> Bool {
        let leads = indentations.filter { $0.contains("|") }
        return lines.contains { line in
            line.reading == .continuation && leads.contains { line.text.hasPrefix($0) }
        }
    }

    /// Whether, in `lines`, a header or a line its message took ends in
    /// white space, which only the end of a whole message drops.
    static func endsInWhiteSpace(_ lines: [GeneratedBuildLine]) -> Bool {
        lines.contains { line in
            opensMessage(line.reading) && line.text.unicodeScalars.last?.properties.isWhitespace == true
        }
    }

    /// Whether, in `lines`, a macro diagnostic's message is followed by a
    /// line with `trait` (`nearOrigin` or `paddedOrigin`), which decides
    /// its origin.
    static func macroBefore(_ trait: BuildLineTrait, in lines: [GeneratedBuildLine]) -> Bool {
        lines.indices.contains { index in
            guard case .diagnostic(let diagnostic) = lines[index].reading, case .macro = diagnostic.location else {
                return false
            }
            let after = lines[(index + 1)...].prefix { $0.reading == .continuation }.count + index + 1
            return lines.indices.contains(after) && lines[after].traits.contains(trait)
        }
    }

    /// The header at `place` with `severity` and `message`, after `decoy`'s
    /// place and severity when there is one: then, by the first-match rule,
    /// the decoy is the place and the rest of the line the message.
    static func headerLine(
        place: HeaderPlace,
        severity: BuildDiagnostic.Severity,
        message: SuffixedText,
        decoy: (FilePlace, BuildDiagnostic.Severity)?
    ) -> BuildLineDraft {
        let line = "\(place.text): \(severity.rawValue): \(message.rendered)"
        guard let (decoyPlace, decoySeverity) = decoy else {
            let shape = BuildLineShape.header(location: place.location, severity: severity, message: message)
            return BuildLineDraft(shape, text: line, traits: place.traits)
        }
        let read = message.with(body: "\(place.text): \(severity.rawValue): \(message.body)")
        return BuildLineDraft(
            .header(location: .file(decoyPlace.place), severity: decoySeverity, message: read),
            text: "\(decoyPlace.text): \(decoySeverity.rawValue): \(line)",
            traits: place.traits.union([.decoyPlace])
        )
    }
}
