//
//  FileContext.swift
//  SwiftStatsCore
//
//  What the collector needs to know about the file it walks but can't learn
//  from the file itself.
//

import SwiftSyntax

/// The file being walked and the target it belongs to.
struct FileContext {
    /// The target (module) name.
    let module: String
    /// The file path, relative to the package root.
    let file: String
    /// Whether the target is a test target.
    let isTestTarget: Bool
    /// Names of classes in the target that descend from `XCTestCase`.
    let testCaseClasses: Set<String>
    /// Converts positions in the file's tree to lines and columns.
    let converter: SourceLocationConverter
    /// Columns to add on line 1: 3 when the file starts with a byte order
    /// mark, which the tree doesn't contain but the compiler counts.
    let firstLineColumnOffset: Int
}
