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
//  limit, which the message never reaches. An origin note follows any
//  header; only a macro header's message reads it, and only when the note
//  comes right after the lines the message took.
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

    /// The severities, the most common first.
    static let severities: [BuildDiagnostic.Severity] = [.warning, .error, .note, .remark]
    /// How an origin note's line is decorated.
    static let originDecorations = ["`- ", "   `- ", "|- "]
    /// The text of the note that names a macro expansion's origin, as
    /// `BuildLineGrammar`'s doc comment states it.
    static let originNote = "expanded code originates here"

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

    /// A diagnostic's first line under `rules`.
    static func header(_ rules: Rules) -> Generator<BuildLineDraft, AnySequence<Any>> {
        zip(
            headerPlace(rules),
            Pick.element(of: severities),
            headerMessage,
            zip(filePlace(.current), Pick.element(of: severities)).optional(valueRate: decoyRate)
        )
        .map(headerLine)
        .eraseToAny()
    }

    /// A macro expansion's origin note under `rules`.
    static func origin(_ rules: Rules) -> Generator<BuildLineDraft, AnySequence<Any>> {
        zip(Pick.element(of: originDecorations), filePlace(rules))
            .map { decoration, place in
                let text = "\(decoration)\(place.text): note: \(originNote)"
                return BuildLineDraft(.origin(place.place), text: text, traits: place.traits)
            }
            .eraseToAny()
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
        let read = SuffixedText(
            body: "\(place.text): \(severity.rawValue): \(message.body)",
            identifier: message.identifier,
            group: message.group
        )
        return BuildLineDraft(
            .header(location: .file(decoyPlace.place), severity: decoySeverity, message: read),
            text: "\(decoyPlace.text): \(decoySeverity.rawValue): \(line)",
            traits: place.traits.union([.decoyPlace])
        )
    }
}
