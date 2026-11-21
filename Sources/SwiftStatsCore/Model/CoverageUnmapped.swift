//
//  CoverageUnmapped.swift
//  SwiftStatsCore
//
//  A coverage export entry in a production target's file that no record,
//  type or file of the scan takes (M5, PRD §7.8), listed with why.
//

/// An export entry the mapping couldn't place.
public struct CoverageUnmapped: Codable, Hashable, Sendable {
    /// Path of the file, relative to the package root.
    public let file: String
    /// The line of its first region's start.
    public let startLine: Int
    /// The column of its first region's start.
    public let startColumn: Int
    /// The line of its first region's end.
    public let endLine: Int
    /// The column of its first region's end, exclusive, as llvm-cov gives it.
    public let endColumn: Int
    /// How often the function was entered; `Int64.max` when saturated.
    public let count: Int64
    /// The mangled name.
    public let name: String
    /// The name demangled by the toolchain's `swift demangle --compact`;
    /// nil when that failed.
    public let demangled: String?
    /// Why: `excluded` or `not parsed` (the scan didn't read the file),
    /// `macro or expansion region`, `region extends past its record`, or
    /// `no code region`.
    public let reason: String

    /// Creates an unmapped entry. Fields are documented on their properties.
    public init(
        file: String,
        startLine: Int,
        startColumn: Int,
        endLine: Int,
        endColumn: Int,
        count: Int64,
        name: String,
        demangled: String?,
        reason: String
    ) {
        self.file = file
        self.startLine = startLine
        self.startColumn = startColumn
        self.endLine = endLine
        self.endColumn = endColumn
        self.count = count
        self.name = name
        self.demangled = demangled
        self.reason = reason
    }

    /// The entry with `demangled` as its demangled name.
    func with(demangled: String?) -> Self {
        Self(
            file: file,
            startLine: startLine,
            startColumn: startColumn,
            endLine: endLine,
            endColumn: endColumn,
            count: count,
            name: name,
            demangled: demangled,
            reason: reason
        )
    }
}
