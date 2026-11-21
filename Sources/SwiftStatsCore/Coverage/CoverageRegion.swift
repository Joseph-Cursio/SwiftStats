//
//  CoverageRegion.swift
//  SwiftStatsCore
//
//  A region of an export entry (M5): `[lineStart, columnStart, lineEnd,
//  columnEnd, count, fileID, expandedFileID, kind]`, columns 1-based in the
//  compiler's UTF-8 columns (a byte order mark's bytes counted on line 1,
//  as records' columns are), the end column exclusive.
//

/// One region of an export entry.
struct CoverageRegion: Decodable, Hashable, Sendable {
    /// LLVM's code region kind.
    static let codeKind = 0
    /// LLVM's expansion region kind (a macro's).
    static let expansionKind = 1
    /// LLVM's skipped region kind (an inactive `#if`).
    static let skippedKind = 2
    /// LLVM's gap region kind.
    static let gapKind = 3

    /// Where it starts.
    let start: SourcePosition
    /// Where it ends; the column is exclusive.
    let end: SourcePosition
    /// How often it ran; `Int64.max` when saturated.
    let executionCount: Int64
    /// Which of the entry's files it is in.
    let fileID: Int
    /// The file it expands, for an expansion region.
    let expandedFileID: Int
    /// What kind of region it is.
    let kind: Int

    /// Whether it is a code region.
    var isCode: Bool {
        kind == Self.codeKind
    }

    /// Whether it is a skipped region.
    var isSkipped: Bool {
        kind == Self.skippedKind
    }

    /// Whether it ran at least once.
    var ran: Bool {
        executionCount > 0
    }

    /// Creates a region. Fields are documented on their properties.
    init(
        start: SourcePosition,
        end: SourcePosition,
        executionCount: Int64,
        fileID: Int,
        expandedFileID: Int,
        kind: Int
    ) {
        self.start = start
        self.end = end
        self.executionCount = executionCount
        self.fileID = fileID
        self.expandedFileID = expandedFileID
        self.kind = kind
    }

    /// Decodes the eight-element array.
    init(from decoder: any Decoder) throws {
        var container = try decoder.unkeyedContainer()
        let startLine = try container.decode(Int.self)
        let startColumn = try container.decode(Int.self)
        let endLine = try container.decode(Int.self)
        let endColumn = try container.decode(Int.self)
        start = SourcePosition(line: startLine, column: startColumn)
        end = SourcePosition(line: endLine, column: endColumn)
        executionCount = try CoverageCount.decode(from: &container)
        fileID = try container.decode(Int.self)
        expandedFileID = try container.decode(Int.self)
        kind = try container.decode(Int.self)
    }

    /// The same region with `executionCount`.
    func with(executionCount: Int64) -> Self {
        Self(
            start: start,
            end: end,
            executionCount: executionCount,
            fileID: fileID,
            expandedFileID: expandedFileID,
            kind: kind
        )
    }
}
