//
//  ProfileShow.swift
//  SwiftStatsCore
//
//  Reads `llvm-profdata show --all-functions --counts` (M5): each function
//  record is a header `  <name>:` indented two spaces, then indented lines
//  of which `Function count: N` is the entry count. A local-linkage name
//  (private, fileprivate, every closure, a property initializer, the
//  runner's `testingLibrary`) is printed `<source path>:$s…`, where the
//  coverage export names the same function `$s…`, so names are normalised.
//

import Foundation

/// Function entry counts from a profile's `show` text.
enum ProfileShow {
    /// The indentation of a function record's header.
    private static let headerIndent = "  "
    /// What precedes a record's entry count.
    private static let countLabel = "Function count:"
    /// The prefixes of a Swift mangled name.
    private static let manglingPrefixes = ["$s", "_$s", "$S"]

    /// The entry count of each function record in `text`, by normalised
    /// name; a count beyond `Int64.max` is kept as `Int64.max`, and a name
    /// listed twice keeps its larger count.
    static func counts(_ text: String) -> [String: Int64] {
        var counts: [String: Int64] = [:]
        var current: String?
        for line in text.split(whereSeparator: \.isNewline) {
            if line.hasPrefix(headerIndent), line.dropFirst(headerIndent.count).first?.isWhitespace == false,
               line.hasSuffix(":") {
                current = normalized(String(line.dropFirst(headerIndent.count).dropLast()))
                continue
            }
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            guard let name = current, trimmed.hasPrefix(countLabel) else {
                continue
            }
            let digits = trimmed.dropFirst(countLabel.count).trimmingCharacters(in: .whitespaces)
            guard let value = UInt64(digits) else {
                continue
            }
            let count = Int64(clamping: value)
            counts[name] = max(counts[name] ?? 0, count)
            current = nil
        }
        return counts
    }

    /// `name` with a source path before its mangled name dropped: when it
    /// holds `:` or `;` and the text after the last one starts as a Swift
    /// mangled name does, that text; otherwise `name` unchanged (a C name
    /// may hold `:`). A mangled name never holds either, so a path that
    /// does is still dropped whole.
    static func normalized(_ name: String) -> String {
        guard let separator = name.lastIndex(where: { $0 == ":" || $0 == ";" }) else {
            return name
        }
        let tail = String(name[name.index(after: separator)...])
        return manglingPrefixes.contains { tail.hasPrefix($0) } ? tail : name
    }
}
