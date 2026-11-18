//
//  SwiftLintViolation.swift
//  SwiftStatsCoreTests
//
//  One entry of `swiftlint lint --reporter json`.
//

/// A SwiftLint violation, as its JSON reporter writes it.
struct SwiftLintViolation: Decodable {
    private enum CodingKeys: String, CodingKey {
        case character, file, line, reason
        case ruleIdentifier = "rule_id"
    }

    /// The file path.
    let file: String
    /// The 1-based line; nil for a whole-file violation.
    let line: Int?
    /// The 1-based column, when reported.
    let character: Int?
    /// "… currently complexity is N" for `cyclomatic_complexity`.
    let reason: String
    /// The rule, such as `force_unwrapping`.
    let ruleIdentifier: String

    /// The complexity at the end of the reason text.
    var complexity: Int? {
        reason.split(separator: " ").last.flatMap { Int($0) }
    }
}
