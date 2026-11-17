//
//  SitrepLines.swift
//  SwiftStatsCore
//
//  Sitrep's line arithmetic. Sitrep splits text on "\n" and keeps lines that
//  are not empty, so a line of spaces counts and a "\r" left by a CRLF ending
//  makes a line non-empty. Counting bytes reproduces that exactly.
//

/// Line counting the way Sitrep does it.
enum SitrepLines {
    /// The newline byte.
    private static let newline = UInt8(ascii: "\n")

    /// Number of "\n" bytes in `text`.
    static func newlineCount(_ text: String) -> Int {
        text.utf8.reduce(0) { count, byte in byte == newline ? count + 1 : count }
    }

    /// Number of "\n"-separated pieces of `text` that are not empty.
    static func nonEmptyLineCount(_ text: String) -> Int {
        var count = 0
        var lineHasContent = false
        for byte in text.utf8 {
            if byte == newline {
                if lineHasContent {
                    count += 1
                }
                lineHasContent = false
            } else {
                lineHasContent = true
            }
        }
        return lineHasContent ? count + 1 : count
    }
}
