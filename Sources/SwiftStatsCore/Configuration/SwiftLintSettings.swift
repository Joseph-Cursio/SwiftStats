//
//  SwiftLintSettings.swift
//  SwiftStatsCore
//
//  The one SwiftLint option the SwiftLint-compatible count honours (PRD
//  §7.3): `cyclomatic_complexity.ignores_case_statements` in the package's
//  `.swiftlint.yml`.
//

import Foundation
import Yams

/// Reads the package's SwiftLint configuration.
enum SwiftLintSettings {
    /// Whether `root/.swiftlint.yml` sets `ignores_case_statements: true`
    /// for `cyclomatic_complexity`; false when it doesn't, or can't be read.
    static func ignoresCaseStatements(packageRoot root: URL) -> Bool {
        let file = root.appendingPathComponent(".swiftlint.yml")
        guard let text = try? String(contentsOf: file, encoding: .utf8),
              let mapping = (try? Yams.load(yaml: text)) as? [String: Any],
              let rule = mapping["cyclomatic_complexity"] as? [String: Any] else {
            return false
        }
        return rule["ignores_case_statements"] as? Bool ?? false
    }
}
