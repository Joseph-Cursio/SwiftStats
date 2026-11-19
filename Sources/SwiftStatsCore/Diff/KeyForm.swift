//
//  KeyForm.swift
//  SwiftStatsCore
//
//  Forms of a function key for matching (PRD §6.6). A file-scoped
//  declaration's key, and every key nested under one, carries ` @ <file>`,
//  and a collision adds `:line` and `:column` after it (PRD §6.1); nested
//  local functions of the same name are numbered ` #2`, ` #3`, ….
//

/// Rewrites keys for matching.
enum KeyForm {
    /// The marker before a file-scoped key's file.
    private static let fileMarker = " @ "
    /// The marker before a sibling's number.
    private static let ordinalMarker = " #"
    /// How many `:number` groups a collision can add.
    private static let maximumLocationGroups = 2

    /// Whether `key` carries ` @ <file>`.
    static func hasFileSegment(_ key: String, file: String) -> Bool {
        key.contains(fileMarker + file)
    }

    /// `key` with each ` @ <file>` and the location after it replaced by
    /// `replacement`.
    static func replacingFileSegments(in key: String, file: String, with replacement: String) -> String {
        let marker = fileMarker + file
        var result = ""
        var rest = Substring(key)
        while let range = rest.range(of: marker) {
            result += rest[..<range.lowerBound] + replacement
            rest = rest[range.upperBound...]
            rest = droppingLocation(rest)
        }
        return result + rest
    }

    /// `key` without its file-scoped parts and location suffixes.
    static func withoutFile(_ key: String, file: String) -> String {
        replacingFileSegments(in: key, file: file, with: "")
    }

    /// `key` without sibling numbers (` #2`) at the end of any segment.
    static func withoutOrdinals(_ key: String) -> String {
        var result = ""
        var rest = Substring(key)
        while let range = rest.range(of: ordinalMarker) {
            let afterMarker = rest[range.upperBound...]
            let digits = afterMarker.prefix(while: \.isNumber)
            let after = afterMarker.dropFirst(digits.count)
            if digits.isEmpty == false, after.isEmpty || after.hasPrefix(" ") {
                result += rest[..<range.lowerBound]
                rest = after
            } else {
                result += rest[..<range.upperBound]
                rest = afterMarker
            }
        }
        return result + rest
    }

    /// `text` without up to two leading `:number` groups.
    private static func droppingLocation(_ text: Substring) -> Substring {
        var rest = text
        for _ in 0..<maximumLocationGroups {
            guard rest.first == ":" else {
                break
            }
            let digits = rest.dropFirst().prefix(while: \.isNumber)
            guard digits.isEmpty == false else {
                break
            }
            rest = rest.dropFirst(1 + digits.count)
        }
        return rest
    }
}
