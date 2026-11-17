//
//  ParsedFile.swift
//  SwiftStatsCore
//
//  A source file read and parsed once, shared by every collector.
//

import SwiftSyntax

/// A file's path, text and syntax tree.
struct ParsedFile {
    /// Path relative to the package root.
    let path: String
    /// The file's text.
    let source: String
    /// The parsed tree.
    let tree: SourceFileSyntax
}
