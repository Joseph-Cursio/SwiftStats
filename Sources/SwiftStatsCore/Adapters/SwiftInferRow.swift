//
//  SwiftInferRow.swift
//  SwiftStatsCore
//
//  One suggestion as one target's `swift-infer index` wrote it, with its
//  location made relative to the package root and its timestamps dropped,
//  ready to merge with the other targets' rows (PRD §7.11).
//

/// A suggestion from one target's index.
struct SwiftInferRow: Equatable, Sendable {
    /// Which of the index's lists it comes from.
    let population: PropertyCandidate.Population
    /// The identity hash, `0x` and 16 uppercase hex digits.
    let identity: String
    /// The template, or an interaction row's family.
    let template: String
    /// The tier as written.
    let tier: String
    /// The score.
    let score: Int
    /// The function as named, or an interaction row's reducer.
    let function: String
    /// The declaring type's lexical path, else its bare name, when given.
    let typeName: String?
    /// `<file>:<line>` with the file relative to the package root, or the
    /// location as written when it names no file in the copy.
    let location: String
    /// Whether the subject is a computed property, located at its `var`.
    let isComputedProperty: Bool
    /// The second function, when the row names one.
    let partner: String?
    /// Why no test can run the law as written, when something stops it.
    let blocker: String?
    /// The hash of the subject's body, which verify evidence must match to
    /// be fresh; nil when the tool couldn't read one.
    let subjectFingerprint: String?
    /// Whether the row carries its carrier's type shape.
    let hasTypeShape: Bool
    /// Every field as written but the timestamps and the location, so two
    /// targets' rows can be compared whole.
    let fields: JSONValue
    /// The target whose run wrote the row.
    let target: String
}
