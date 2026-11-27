//
//  BuildOutputGen+Footnotes.swift
//  SwiftStatsCoreTests
//
//  Diagnostic blocks around a group's footnote, `[#Group]: <https://…>`,
//  each a block of its own so P1.5 meets it in every run: a message with
//  no ID ended by an empty line or a footnote, a plain line after it,
//  which the line before keeps out of the message; and a message with no
//  ID taking a line that is a footnote but for one part (led by `[#` with
//  no `]: <` or no closing `>`, or ending `>` but not led by `[#`). No
//  text starts `[#` or ends `>`, so a line is a near footnote only where
//  this block wrote one.
//

import PropertyBased
@testable import SwiftStatsCore

extension BuildOutputGen {
    /// A line that is a group's footnote, `[#Group]: <https://…>`, but for
    /// one part, so it can continue a message. No text starts `[#` or ends
    /// `>`, so a line is one of these only where a block wrote it.
    enum NearFootnote: CaseIterable, Sendable {
        /// `[#<word>`: no `]: <` and no closing `>`.
        case opened
        /// `[#<word>>`: no `]: <`.
        case closed
        /// `[#<word>]: <<word>`: no closing `>`.
        case unclosed
        /// `<word><<word>>`, a generic type: not led by `[#`.
        case generic

        /// What P1.5's tally counts when a message takes a line of this
        /// form.
        var label: String {
            switch self {
            case .opened:
                "a message taking a line led by [# alone"

            case .closed:
                "a message taking a line led by [# and ending in >"

            case .unclosed:
                "a message taking a line led by [# and holding ]: < with no closing >"

            case .generic:
                "a message taking a line ending in > not led by [#"
            }
        }

        /// The form of `text`, a line written by `text(_:_:)`; nil for a
        /// line no form writes.
        static func form(of text: String) -> Self? {
            guard text.hasPrefix("[#") else {
                return text.hasSuffix(">") ? .generic : nil
            }
            if text.contains("]: <") {
                return .unclosed
            }
            return text.hasSuffix(">") ? .closed : .opened
        }

        /// The line of this form around `first` and `second`.
        func text(_ first: String, _ second: String) -> String {
            switch self {
            case .opened:
                "[#\(first)"

            case .closed:
                "[#\(first)>"

            case .unclosed:
                "[#\(first)]: <\(second)"

            case .generic:
                "\(first)<\(second)>"
            }
        }
    }

    /// A diagnostic whose message has no ID or group, then a line that is
    /// a footnote but for one part, which the message takes (a block of
    /// its own, so P1.5 meets each form often).
    static func nearFootnoted(_ rules: Rules) -> Generator<[BuildLineDraft], AnySequence<Any>> {
        zip(
            headerPlace(rules),
            Pick.element(of: severities),
            text,
            Pick.element(of: NearFootnote.allCases),
            word,
            word
        )
        .map { place, severity, body, form, first, second in
            let line = SuffixedText(form.text(first, second))
            return [
                headerLine(place: place, severity: severity, message: SuffixedText(body), decoy: nil),
                BuildLineDraft(.plain(line), text: line.rendered, traits: [])
            ]
        }
        .eraseToAny()
    }

    /// Whether, in `lines`, a message takes a line of `form`.
    static func takesNearFootnote(_ form: NearFootnote, in lines: [GeneratedBuildLine]) -> Bool {
        lines.contains { $0.reading == .continuation && NearFootnote.form(of: $0.text) == form }
    }

    /// A diagnostic whose message has no ID or group, an empty line or a
    /// group's footnote, and a plain line, which the line before keeps out
    /// of the message (a block of its own, so P1.5 meets both often).
    static func stopEnded(_ rules: Rules) -> Generator<[BuildLineDraft], AnySequence<Any>> {
        zip(
            headerPlace(rules),
            Pick.element(of: severities),
            text,
            Gen.frequency(
                (classWeight, Gen.always(BuildLineDraft(.blank, text: "", traits: []))),
                (classWeight, footnote.map { BuildLineDraft(.stopper, text: $0, traits: []) })
            ),
            continuation
        )
        .map { place, severity, body, stop, after in
            [headerLine(place: place, severity: severity, message: SuffixedText(body), decoy: nil), stop, after]
        }
        .eraseToAny()
    }

    /// Whether, in `lines`, an empty line written with LF alone comes right
    /// after a header or a line its message took, a plain line after it:
    /// the empty line ends the message, the antecedent P1.5 needs for it.
    static func endsAtEmptyLine(_ lines: [GeneratedBuildLine]) -> Bool {
        lines.indices.dropFirst().dropLast().contains { index in
            let empty = lines[index]
            return empty.written.isEmpty && empty.lineBreak == "\n"
                && opensMessage(lines[index - 1].reading) && lines[index + 1].shape.continuesMessage
        }
    }

    /// Whether, in `lines`, a group's footnote comes right after a header
    /// whose message has no ID or group: the footnote ends the message, the
    /// antecedent P1.5 needs for it.
    static func endsAtFootnote(_ lines: [GeneratedBuildLine]) -> Bool {
        zip(lines, lines.dropFirst()).contains { header, footnote in
            guard case .diagnostic(let diagnostic) = header.reading, footnote.shape == .stopper,
                  footnote.text.hasPrefix("[#")
            else {
                return false
            }
            return diagnostic.identifier == nil && diagnostic.group == nil
        }
    }
}
