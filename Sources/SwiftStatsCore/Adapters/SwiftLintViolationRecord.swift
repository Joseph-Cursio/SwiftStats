//
//  SwiftLintViolationRecord.swift
//  SwiftStatsCore
//
//  One entry of `swiftlint lint --reporter json` (PRD §7.7).
//

/// One SwiftLint violation as its JSON reporter writes it.
struct SwiftLintViolationRecord: Decodable {
    private enum CodingKeys: String, CodingKey {
        case character, file, line, reason, severity, type
        case ruleIdentifier = "rule_id"
    }

    /// 1-based column, when the violation has one.
    let character: Int?
    /// Absolute path; nil for a violation not tied to a file.
    let file: String?
    /// 1-based line, when the violation has one.
    let line: Int?
    /// The message.
    let reason: String
    /// The rule's identifier, such as `force_unwrapping`.
    let ruleIdentifier: String
    /// `Warning` or `Error`.
    let severity: String
    /// The rule's display name.
    let type: String
}
