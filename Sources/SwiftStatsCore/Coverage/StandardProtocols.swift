//
//  StandardProtocols.swift
//  SwiftStatsCore
//
//  What the link rule of tests per public function knows about the
//  standard library's protocols (M5), all of it decided from syntax: which
//  names are protocols, so an extension of one holds protocol extension
//  members; which protocols refine which; and the requirements of the
//  protocols whose witnesses tests reach generically (`Sequence`,
//  `Collection`, `BidirectionalCollection`, `RandomAccessCollection`,
//  `IteratorProtocol`, `Equatable`, `Hashable`, `Comparable`,
//  `CustomStringConvertible`), as `MemberSelector` writes them.
//

/// The standard protocols the link rule knows.
enum StandardProtocols {
    /// The requirements whose witnesses are reached generically, by protocol.
    static let requirements: [String: Set<String>] = [
        "Sequence": ["makeIterator()", "underestimatedCount", "withContiguousStorageIfAvailable(_:)"],
        "Collection": [
            "startIndex", "endIndex", "indices", "isEmpty", "count", "subscript(_:)",
            "index(after:)", "formIndex(after:)", "index(_:offsetBy:)", "index(_:offsetBy:limitedBy:)",
            "formIndex(_:offsetBy:)", "formIndex(_:offsetBy:limitedBy:)", "distance(from:to:)"
        ],
        "BidirectionalCollection": ["index(before:)", "formIndex(before:)"],
        "RandomAccessCollection": [],
        "IteratorProtocol": ["next()"],
        "Equatable": ["static =="],
        "Hashable": ["hash(into:)", "hashValue"],
        "Comparable": ["static <", "static <=", "static >", "static >="],
        "CustomStringConvertible": ["description"]
    ]

    /// The protocols each standard protocol refines, directly.
    static let refinements: [String: [String]] = [
        "Collection": ["Sequence"],
        "BidirectionalCollection": ["Collection"],
        "RandomAccessCollection": ["BidirectionalCollection"],
        "MutableCollection": ["Collection"],
        "RangeReplaceableCollection": ["Collection"],
        "LazySequenceProtocol": ["Sequence"],
        "LazyCollectionProtocol": ["Collection", "LazySequenceProtocol"],
        "Hashable": ["Equatable"],
        "Comparable": ["Equatable"],
        "Strideable": ["Comparable"],
        "StringProtocol": ["BidirectionalCollection", "Comparable", "Hashable", "CustomStringConvertible"],
        "SetAlgebra": ["Equatable"],
        "OptionSet": ["SetAlgebra", "RawRepresentable"],
        "BinaryInteger": ["Hashable", "Strideable", "CustomStringConvertible"],
        "FloatingPoint": ["Hashable", "Strideable"]
    ]

    /// The standard library's and Foundation's protocols an extension
    /// commonly extends.
    static let names: Set<String> = [
        "Actor", "AdditiveArithmetic", "AsyncIteratorProtocol", "AsyncSequence", "BidirectionalCollection",
        "BinaryFloatingPoint", "BinaryInteger", "CaseIterable", "Clock", "CodingKey", "Collection", "Comparable",
        "ContiguousBytes", "CustomDebugStringConvertible", "CustomReflectable", "CustomStringConvertible",
        "DataProtocol", "Decodable", "Decoder", "DurationProtocol", "Encodable", "Encoder", "Equatable", "Error",
        "ExpressibleByArrayLiteral", "ExpressibleByBooleanLiteral", "ExpressibleByDictionaryLiteral",
        "ExpressibleByFloatLiteral", "ExpressibleByIntegerLiteral", "ExpressibleByNilLiteral",
        "ExpressibleByStringInterpolation", "ExpressibleByStringLiteral", "FixedWidthInteger", "FloatingPoint",
        "Hashable", "Identifiable", "InstantProtocol", "IteratorProtocol", "LazyCollectionProtocol",
        "LazySequenceProtocol", "LosslessStringConvertible", "MutableCollection", "MutableDataProtocol",
        "Numeric", "OptionSet", "RandomAccessCollection", "RandomNumberGenerator", "RangeExpression",
        "RangeReplaceableCollection", "RawRepresentable", "Sendable", "Sequence", "SetAlgebra", "SignedInteger",
        "SignedNumeric", "Strideable", "StringProtocol", "TextOutputStream", "TextOutputStreamable",
        "UnsignedInteger"
    ]
}
