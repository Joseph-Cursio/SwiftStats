//
//  BuildOutputGen+Timing.swift
//  SwiftStatsCoreTests
//
//  Timing lines. A valid one is `<time>ms<TAB><place>`, then a tab and a
//  declaration for a function body, with a time of one to twelve whole
//  digits (B1's bound; a leading zero sometimes, the bound itself among
//  the edges) and none, one or two fraction digits; its entry is computed
//  from the drawn numbers, never parsed. A malformed one holds `ms<TAB>`
//  and states no entry: one fault in the time (none, signed, fullwidth
//  digits, an empty or three-digit fraction) or in the fields (an empty
//  declaration, a fourth field, a place without its column, starting with
//  a space, or `<invalid>`). An overlong one is valid but for 13 or more
//  whole digits, so it still ends a message. Under the decided rules a
//  Prepend scalar may come just before `ms` (B23, pending).
//

import PropertyBased
@testable import SwiftStatsCore

extension BuildOutputGen {
    /// A time as written and as read.
    struct Time: Sendable {
        /// As written, without its unit.
        let text: String
        /// As read, in hundredths of a millisecond.
        let hundredths: Int
    }

    /// A fault in a timing line's time.
    enum TimeFault: CaseIterable, Sendable {
        /// No time before the unit.
        case bare
        /// A point with no fraction digits.
        case emptyFraction
        /// Fullwidth digits.
        case fullwidthDigits
        /// A fraction with no whole digits.
        case noWhole
        /// A minus sign.
        case signed
        /// Three fraction digits.
        case threeFraction

        /// The fullwidth digits, zero first.
        static let fullwidth = Array("０１２３４５６７８９")

        /// The time field `time` gives with this fault, unit included.
        func field(_ time: Time) -> String {
            let wholeText = String(time.text.prefix { $0 != "." })
            return switch self {
            case .bare:
                "ms"

            case .emptyFraction:
                wholeText + ".ms"

            case .fullwidthDigits:
                String(wholeText.compactMap { $0.wholeNumberValue.map { Self.fullwidth[$0] } }) + "ms"

            case .noWhole:
                ".5ms"

            case .signed:
                "-" + time.text + "ms"

            case .threeFraction:
                wholeText + ".125ms"
            }
        }
    }

    /// A fault in a timing line's fields after the time.
    enum FieldFault: CaseIterable, Sendable {
        /// A third field, empty.
        case emptyDeclaration
        /// A fourth field.
        case extraField
        /// `<invalid>` in place of `<invalid loc>`.
        case misspelledInvalid
        /// A place without its column.
        case noColumn
        /// A place starting with a space.
        case spacedPath

        /// The fields after the time that `place` gives with this fault.
        func fields(_ place: FilePlace) -> String {
            switch self {
            case .emptyDeclaration:
                place.text + "\t"

            case .extraField:
                place.text + "\tfunc\textra"

            case .misspelledInvalid:
                "<invalid>"

            case .noColumn:
                "\(place.place.path):\(place.place.line)"

            case .spacedPath:
                " " + place.text
            }
        }
    }

    /// Weight of small times, the most common in a real build.
    static let smallTimeWeight = 3.0
    /// The share of timing lines with a declaration (a function body's).
    static let declarationRate: Float = 0.4

    /// The most whole digits a time has (forced: B1's bound).
    static let wholeDigits = 12
    /// The largest time with that many digits (forced, as above).
    static let largestWhole = 999_999_999_999
    /// The largest small time (assumed: most type-check times are under a
    /// second).
    static let smallWhole = 999
    /// How many whole digits an overlong time has (forced: one past the
    /// bound; the top is assumed).
    static let overlongDigits = (wholeDigits + 1)...20
    /// The largest one-digit fraction.
    static let largestTenth = 9
    /// The largest two-digit fraction.
    static let largestHundredth = 99
    /// Hundredths in a millisecond.
    static let hundredthsPerMillisecond = 100
    /// Hundredths in a tenth.
    static let hundredthsPerTenth = 10
    /// The ASCII digits.
    static let digits = Array("0123456789")
    /// The kinds a function body's declaration names.
    static let declarationKinds = ["global function", "instance method", "getter", "initializer", "_modify accessor"]

    /// A whole number of milliseconds within the bound: small ones mostly,
    /// any up to the bound, and the edges.
    static let whole = Gen.frequency(
        (smallTimeWeight, Gen<Int>.value(in: 0...smallWhole)),
        (classWeight, Gen<Int>.value(in: 0...largestWhole)),
        (classWeight, Pick.element(of: [0, largestWhole]))
    )

    /// No fraction, one digit or two.
    static let fraction = Gen.frequency(
        (classWeight, Gen.always(Time(text: "", hundredths: 0))),
        (classWeight, Gen<Int>.value(in: 0...largestTenth).map { tenths in
            Time(text: ".\(tenths)", hundredths: tenths * hundredthsPerTenth)
        }),
        (classWeight, Gen<Int>.value(in: 0...largestHundredth).map(twoDigitFraction))
    )

    /// A time within the bound.
    static let time = zip(whole, Gen.bool(paddedRate), fraction)
        .map { value, padded, fraction in
            let written = String(value)
            let padding = padded && written.count < wholeDigits ? "0" : ""
            let hundredths = value * hundredthsPerMillisecond + fraction.hundredths
            return Time(text: padding + written + fraction.text, hundredths: hundredths)
        }

    /// A function body's declaration: `<kind> <Module>.(file).<name>()@<place>`.
    static let declaration = zip(Pick.element(of: declarationKinds), word, word, filePlace(.current))
        .map { kind, module, name, place in "\(kind) \(module).(file).\(name)()@\(place.text)" }

    /// A timing line with one fault, holding `ms<TAB>`.
    static let malformedTiming = Gen.frequency(
        (classWeight, zip(Pick.element(of: TimeFault.allCases), time, timingPlace(.current)).map { fault, time, place in
            fault.field(time) + "\t" + (place?.text ?? invalidLocation)
        }),
        (classWeight, zip(Pick.element(of: FieldFault.allCases), time, filePlace(.current)).map { fault, time, place in
            time.text + "ms\t" + fault.fields(place)
        })
    )
    .map { BuildLineDraft(.malformedTiming, text: $0, traits: []) }

    /// A timing line but for a time past the bound.
    static let overlongTiming = zip(
        Pick.element(of: digits).array(of: overlongDigits),
        fraction,
        timingPlace(.current),
        declaration.optional(valueRate: declarationRate)
    )
    .map { whole, fraction, place, declaration in
        let field = String(whole) + fraction.text + "ms"
        let fields = [field, place?.text ?? invalidLocation] + [declaration].compactMap(\.self)
        return BuildLineDraft(.overlongTiming, text: fields.joined(separator: "\t"), traits: [])
    }

    /// A time with a Prepend scalar just before its `ms` (B23, pending).
    static let prependedTime = zip(time, Pick.element(of: UnicodeGen.prepend), timingPlace(.current))
        .map { time, prepend, place in
            let text = time.text + prepend + "ms\t" + (place?.text ?? invalidLocation)
            return BuildLineDraft(.malformedTiming, text: text, traits: [.pendingB23])
        }

    /// A valid timing line under `rules`.
    static func timing(_ rules: Rules) -> Generator<BuildLineDraft, AnySequence<Any>> {
        zip(time, timingPlace(rules), declaration.optional(valueRate: declarationRate))
            .map { time, place, declaration in
                let entry = TimingEntry(
                    kind: declaration == nil ? .expression : .function,
                    hundredths: time.hundredths,
                    place: place?.place,
                    declaration: declaration
                )
                let fields = [time.text + "ms", place?.text ?? invalidLocation] + [declaration].compactMap(\.self)
                return BuildLineDraft(.timing(entry), text: fields.joined(separator: "\t"), traits: place?.traits ?? [])
            }
            .eraseToAny()
    }

    /// A two-digit fraction of `value` hundredths.
    static func twoDigitFraction(_ value: Int) -> Time {
        Time(text: "." + (value < hundredthsPerTenth ? "0" : "") + String(value), hundredths: value)
    }
}
