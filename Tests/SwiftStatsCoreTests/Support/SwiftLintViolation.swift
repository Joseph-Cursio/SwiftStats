//
//  SwiftLintViolation.swift
//  SwiftStatsCoreTests
//
//  One entry of `swiftlint lint --reporter json`.
//

/// A SwiftLint violation, as its JSON reporter writes it.
struct SwiftLintViolation: Decodable {
    /// The file path.
    let file: String
    /// The 1-based line.
    let line: Int
    /// The 1-based column, when reported.
    let character: Int?
    /// "… currently complexity is N".
    let reason: String

    /// The complexity at the end of the reason text.
    var complexity: Int? {
        reason.split(separator: " ").last.flatMap { Int($0) }
    }
}
