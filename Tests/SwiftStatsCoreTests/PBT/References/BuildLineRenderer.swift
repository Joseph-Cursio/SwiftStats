//
//  BuildLineRenderer.swift
//  SwiftStatsCoreTests
//
//  Writes a timing entry as the line the compiler prints for it, from the
//  timing grammar `BuildLineGrammar`'s header states (M7 design §6.1), not
//  from its code: a time `<digits>[.<one or two digits>]ms` with at most
//  twelve whole digits, a tab, `<invalid loc>` or `<path>:<line>:<column>`,
//  and for a function body a tab and its declaration. P1.4's reference: a
//  time can be written whole, with one fraction digit or with two, and
//  with leading zeros, so the round trip reaches every form the grammar
//  states, and a line or column can be written with a leading zero, which
//  the grammar reads as the same number.
//

@testable import SwiftStatsCore

/// Writes timing entries as build-output timing lines.
enum BuildLineRenderer {
    /// How many fraction digits a time is written with.
    enum TimeForm: CaseIterable, Hashable, Sendable {
        /// One fraction digit, when the hundredths are a whole tenth.
        case tenths
        /// Two fraction digits, always possible.
        case twoDigits
        /// No fraction, when the hundredths are a whole millisecond.
        case whole
    }

    /// How an entry is written: its time's form, the zeros before its whole
    /// digits, and whether its line and column take a leading zero.
    struct Style: Hashable, Sendable {
        /// Two fraction digits, no padding: one way every entry can be
        /// written.
        static let plain = Self(form: .twoDigits, padding: 0, paddedNumbers: false)

        /// The form of the time.
        let form: TimeForm
        /// The zeros before the time's whole digits, up to the twelve the
        /// grammar takes.
        let padding: Int
        /// Whether the line and column are written with a leading zero.
        let paddedNumbers: Bool
    }

    /// What a timing line holds in place of a location, as the grammar's
    /// doc comment states it.
    static let invalidLocation = "<invalid loc>"
    /// What follows a time.
    static let unit = "ms"
    /// What separates a timing line's fields.
    static let separator = "\t"
    /// The most whole digits a time the grammar takes has, as its doc
    /// comment states.
    static let wholeDigits = 12
    /// Hundredths of a millisecond in one.
    static let hundredthsPerMillisecond = 100
    /// Hundredths of a millisecond in a tenth.
    static let hundredthsPerTenth = 10

    /// `entry` written in `style`: the time, the place or `<invalid loc>`,
    /// and the declaration when it has one.
    static func line(_ entry: TimingEntry, style: Style) -> String {
        let location = entry.place.map { place(of: $0, padded: style.paddedNumbers) } ?? invalidLocation
        let fields = [time(entry.hundredths, style: style), location] + [entry.declaration].compactMap(\.self)
        return fields.joined(separator: separator)
    }

    /// `hundredths` written as a time with its unit, in `style`'s form when
    /// the value allows it (otherwise with two fraction digits), and with
    /// as many of `style`'s leading zeros as keep the whole part within
    /// twelve digits.
    static func time(_ hundredths: Int, style: Style) -> String {
        let whole = String(hundredths / hundredthsPerMillisecond)
        let fraction = hundredths % hundredthsPerMillisecond
        let zeros = String(repeating: "0", count: max(0, min(style.padding, wholeDigits - whole.count)))
        let fractionText = switch style.form {
        case .whole where fraction == 0:
            ""

        case .tenths where fraction.isMultiple(of: hundredthsPerTenth):
            "." + String(fraction / hundredthsPerTenth)

        default:
            "." + (fraction < hundredthsPerTenth ? "0" : "") + String(fraction)
        }
        return zeros + whole + fractionText + unit
    }

    /// `place` written `<path>:<line>:<column>`, the numbers with a
    /// leading zero when `padded`.
    static func place(of place: BuildPlace, padded: Bool) -> String {
        let zero = padded ? "0" : ""
        return "\(place.path):\(zero)\(place.line):\(zero)\(place.column)"
    }
}
