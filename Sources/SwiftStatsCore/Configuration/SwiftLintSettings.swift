//
//  SwiftLintSettings.swift
//  SwiftStatsCore
//
//  The one SwiftLint option the SwiftLint-compatible count honours (PRD
//  §7.3): `cyclomatic_complexity.ignores_case_statements` in the package's
//  `.swiftlint.yml`. The file is composed and only that value is read, as
//  Yams' `load` would read it: building every value with `load` traps on
//  a base-60 integer past `Int` or a key that isn't text anywhere in the
//  file (design B30).
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
              let document = try? Yams.compose(yaml: text),
              let rule = value(named: "cyclomatic_complexity", in: document),
              let setting = value(named: "ignores_case_statements", in: rule),
              setting.tag == Tag(.bool),
              let scalar = setting.scalar else {
            return false
        }
        // A YAML 1.1 boolean (`true`, `yes`, `on`, any case Yams resolves);
        // one tagged `!!bool` that isn't such a word is text to Yams.
        return Bool.construct(from: scalar) ?? false
    }

    /// The value `node` gives the key `name` when Yams' `load` reads it as
    /// a dictionary: a mapping not tagged `!!set`, keys compared by their
    /// text whatever their tag or quotes, a key that isn't text skipped,
    /// and the last pair for a key winning; nil for anything else.
    private static func value(named name: String, in node: Node) -> Node? {
        guard let mapping = node.mapping, node.tag != Tag(.set) else {
            return nil
        }
        return pairs(of: mapping).last { String.construct(from: $0.key) == name }?.value
    }

    /// `mapping`'s pairs in the order Yams' `load` takes them: the pairs
    /// its merge keys (`<<`) bring in first, a merged list's mappings last
    /// to first, then the mapping's own pairs, so an own pair wins.
    private static func pairs(of mapping: Node.Mapping) -> [(key: Node, value: Node)] {
        var merged: [(key: Node, value: Node)] = []
        var own: [(key: Node, value: Node)] = []
        for pair in mapping {
            guard pair.key.tag == Tag(.merge) else {
                own.append(pair)
                continue
            }
            switch pair.value {
            case .mapping(let source):
                merged += pairs(of: source)

            case .sequence(let sources):
                for source in sources.compactMap(\.mapping).reversed() {
                    merged += pairs(of: source)
                }

            default:
                break
            }
        }
        return merged + own
    }
}
