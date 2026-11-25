//
//  PeripheryFields.swift
//  SwiftStatsCore
//
//  The nine fields of one outskirts JSON entry, checked for type before
//  `PeripheryOutput` reads them (M7, design §5.3): the string fields, the
//  list fields and the location, read from the right as
//  `path:line:column`, so a path holding colons reads whole.
//

/// One outskirts entry's fields, by key.
struct PeripheryFields {
    /// An entry's location.
    struct Location: Hashable {
        /// How many colon-separated numbers end a location: the line and
        /// the column.
        private static let numberParts = 2

        /// The file's path, as outskirts wrote it.
        let path: String
        /// The 1-based line.
        let line: Int
        /// The 1-based UTF-8 column.
        let column: Int

        /// A location at `line` and `column` of `path`.
        init(path: String, line: Int, column: Int) {
            self.path = path
            self.line = line
            self.column = column
        }

        /// `text` read from the right as `path:line:column`, with a
        /// non-empty path and a positive line and column; nil otherwise.
        init?(_ text: String) {
            let parts = text.split(separator: ":", omittingEmptySubsequences: false)
            let numbers = parts.suffix(Self.numberParts).compactMap(Self.positive)
            let written = parts.dropLast(Self.numberParts).joined(separator: ":")
            guard numbers.count == Self.numberParts, let first = numbers.first, let last = numbers.last,
                  written.isEmpty == false else {
                return nil
            }
            self.init(path: written, line: first, column: last)
        }

        /// `part` as a positive number of decimal digits; nil otherwise.
        private static func positive(_ part: Substring) -> Int? {
            guard part.isEmpty == false, part.allSatisfy({ $0.isASCII && $0.isNumber }),
                  let number = Int(part), number > 0 else {
                return nil
            }
            return number
        }
    }

    /// The string fields, by key.
    var strings: [String: String] = [:]
    /// The list fields, by key.
    var lists: [String: [String]] = [:]
    /// The location; set once the fields are checked.
    var location = Location(path: "", line: 0, column: 0)
}
