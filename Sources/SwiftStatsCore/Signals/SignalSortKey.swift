//
//  SignalSortKey.swift
//  SwiftStatsCore
//
//  The order a signal lists its items in: fields compared in turn, the
//  first that differs deciding. Most signals list by score, highest first,
//  then by subject, file and line; a signal with its own order states it.
//  A share (M6's function scores and line coverage) is compared by
//  cross-multiplying its integers, so equal shares tie exactly and the
//  order never rests on a rounded quotient.
//

/// Where an item sorts in its signal.
struct SignalSortKey: Comparable, Hashable, Sendable {
    /// One field of a key.
    enum Field: Comparable, Hashable, Sendable {
        /// A number, lowest first.
        case number(Double)
        /// A share, `part` of `whole` with `whole` above 0, lowest first,
        /// kept in lowest terms so equal shares are equal fields.
        case share(part: Int, whole: Int)
        /// Text, in `String`'s order.
        case text(String)

        /// The name of a field's case, ordering fields of different cases
        /// (which one signal's keys never compare) in the cases' order.
        private var kind: String {
            switch self {
            case .number:
                "number"

            case .share:
                "share"

            case .text:
                "text"
            }
        }

        /// `part` of `whole` (above 0) as a share field, in lowest terms.
        static func fraction(_ part: Int, of whole: Int) -> Self {
            var (larger, smaller) = (Swift.max(part, whole), Swift.min(part, whole))
            while smaller > 0 {
                (larger, smaller) = (smaller, larger % smaller)
            }
            let divisor = Swift.max(larger, 1)
            return .share(part: part / divisor, whole: whole / divisor)
        }

        /// Whether `lhs` sorts before `rhs`: numbers and text as such,
        /// shares by cross-multiplying, else by case.
        static func < (lhs: Self, rhs: Self) -> Bool {
            switch (lhs, rhs) {
            case let (.number(left), .number(right)):
                left < right

            case let (.share(leftPart, leftWhole), .share(rightPart, rightWhole)):
                leftPart * rightWhole < rightPart * leftWhole

            case let (.text(left), .text(right)):
                left < right

            default:
                lhs.kind < rhs.kind
            }
        }
    }

    /// The fields, compared in turn.
    let fields: [Field]

    /// A key of `fields`.
    init(_ fields: [Field]) {
        self.fields = fields
    }

    /// The default order: score, highest first, then subject, file and line.
    static func standard(score: Double, subject: String, file: String, line: Int) -> Self {
        Self([.number(-score), .text(subject), .text(file), .number(Double(line))])
    }

    /// Whether `lhs` sorts before `rhs`.
    static func < (lhs: Self, rhs: Self) -> Bool {
        lhs.fields.lexicographicallyPrecedes(rhs.fields)
    }

    /// This key with `field` compared last, to break its remaining ties.
    func appending(_ field: Field) -> Self {
        Self(fields + [field])
    }
}
