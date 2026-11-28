//
//  ExportDraft.swift
//  SwiftStatsCoreTests
//
//  An `llvm-cov export` document as decisions, P2.6's input: files with
//  their segments (each a step from the one before, so sorted by line,
//  then column, two sharing a position when a step is 0), function entries
//  with their files and regions, counts spelled within `Int64`, past
//  `Int64.max` up to `UInt64.max`, or in a form whose reading isn't
//  labelled (`3.0`, `1e2`), rows longer than llvm writes them, the members
//  llvm writes that the decoder doesn't read, and at most one fault: the
//  wrong type or version, no data element or two, a file whose segments go
//  back, a key missing or of the wrong type, a row too short, a count past
//  `UInt64.max` or below `Int64.min`, the document cut short, or one byte
//  changed. A fault's target is the first file, segment, entry or region;
//  one is added when there is none (`normalized`). `expected` is what the
//  decoder's documented reading gives: the export, with every count past
//  `Int64.max` read as `Int64.max` (`CoverageCount`), one of its reasons,
//  or, for a changed byte or an unlabelled spelling, anything but a trap
//  or another error. The document itself is in `ExportDraft+Document`.
//

@testable import SwiftStatsCore

/// An export document as decisions.
struct ExportDraft: Hashable, Sendable {
    /// A count as the document spells it.
    enum Count: Hashable, Sendable {
        /// Past `Int64.max`, within `UInt64`.
        case clamped(UInt64)
        /// A spelling whose reading isn't labelled.
        case spelled(String)
        /// Within `Int64`.
        case value(Int64)
    }

    /// The one fault a document may have.
    enum Fault: Hashable, Sendable {
        /// The byte at this offset, modulo the length, becomes this one.
        case badByte(offset: Int, byte: UInt8)
        /// The data array holds this many elements, not one.
        case dataCount(Int)
        /// The first file's segments end with one before the last.
        case misordered
        /// The first object holding this key lacks it.
        case missing(String)
        /// The first value under this key, or in this field of a row, has
        /// the wrong type.
        case mistyped(String)
        /// The first count of this kind of row is spelled out of range.
        case outOfRange(target: String, spelling: String)
        /// The first row of this kind is one element short.
        case shortRow(String)
        /// No fault.
        case sound
        /// The document is cut at this offset, modulo its length.
        case truncated(Int)
        /// The type is this one.
        case wrongType(String)
        /// The version is this one.
        case wrongVersion(String)
    }

    /// A segment as decisions.
    struct Segment: Hashable, Sendable {
        /// Lines after the segment before it (from line 1 for the first).
        let lineStep: Int
        /// Columns after the one before it on its line, or after column 1.
        let columnStep: Int
        /// Its count.
        let count: Count
        /// Whether it carries a count.
        let hasCount: Bool
        /// Whether it enters a region.
        let isRegionEntry: Bool
        /// Whether it enters a gap region.
        let isGapRegion: Bool
        /// How many elements follow the six llvm writes.
        let extras: Int
    }

    /// A region as decisions.
    struct Region: Hashable, Sendable {
        /// Where it starts.
        let start: SourcePosition
        /// Where it ends.
        let end: SourcePosition
        /// Its count.
        let count: Count
        /// Its file ID.
        let fileID: Int
        /// Its kind, possibly one llvm doesn't define.
        let kind: Int
        /// How many elements follow the eight llvm writes.
        let extras: Int
    }

    /// A file as decisions.
    struct File: Hashable, Sendable {
        /// Its name's index in `CoverageExportGen.filenames`.
        let name: Int
        /// Its segments.
        let segments: [Segment]
    }

    /// A function entry as decisions.
    struct Function: Hashable, Sendable {
        /// Its name's index in `CoverageExportGen.functionNames`.
        let name: Int
        /// Its entry count.
        let count: Count
        /// Its files' indices in `CoverageExportGen.filenames`.
        let files: [Int]
        /// Its regions.
        let regions: [Region]
    }

    /// What decoding the document should give.
    enum Expected: Equatable, Sendable {
        /// These files and entries.
        case accepted(files: [CoverageExportFile], functions: [CoverageExportFunction])
        /// A `CoverageFailure` with exactly this reason.
        case refused(String)
        /// Anything but a trap, or an error other than a `CoverageFailure`.
        case unknown
        /// A `CoverageFailure` reading the document failed.
        case unreadable
    }

    /// The prefix of every reason for a document that doesn't decode.
    static let unreadablePrefix = "could not read `llvm-cov export`'s output: "
    /// A segment added where a fault needs one.
    static let addedSegment = Segment(
        lineStep: 0,
        columnStep: 0,
        count: .value(1),
        hasCount: true,
        isRegionEntry: true,
        isGapRegion: false,
        extras: 0
    )
    /// A region added where a fault needs one: empty, at line 1, which the
    /// decoder reads as any other.
    static let addedRegion = Region(
        start: SourcePosition(line: 1, column: 1),
        end: SourcePosition(line: 1, column: 1),
        count: .value(1),
        fileID: 0,
        kind: CoverageRegion.codeKind,
        extras: 0
    )
    /// The keys and fields whose fault needs a file.
    static let fileTargets: Set<String> = ["filename", "segments", "segmentLine", "segmentFlag", "segment"]
    /// Those whose fault needs a segment.
    static let segmentTargets: Set<String> = ["segmentLine", "segmentFlag", "segment"]
    /// Those whose fault needs a function entry.
    static let functionTargets: Set<String> = [
        "name", "count", "filenames", "regions", "regionKind", "region", "function"
    ]
    /// Those whose fault needs a region.
    static let regionTargets: Set<String> = ["regionKind", "region"]

    /// The files.
    let files: [File]
    /// The function entries.
    let functions: [Function]
    /// Whether objects hold the members llvm writes that aren't read.
    let extraKeys: Bool
    /// The fault.
    let fault: Fault

    /// The key, field or row kind the fault is about; nil when it is
    /// about the document as a whole.
    var target: String? {
        switch fault {
        case .misordered:
            return "segment"

        case let .missing(key), let .mistyped(key), let .shortRow(key):
            return key

        case .outOfRange(let target, _):
            return target

        case .badByte, .dataCount, .sound, .truncated, .wrongType, .wrongVersion:
            return nil
        }
    }

    /// The draft with a file, segment, entry or region added first where
    /// its fault needs one and there is none.
    var normalized: Self {
        guard let target else {
            return self
        }
        var files = files
        var functions = functions
        if Self.fileTargets.contains(target), files.isEmpty {
            files = [File(name: 0, segments: [])]
        }
        if Self.segmentTargets.contains(target), files[0].segments.isEmpty {
            files[0] = File(name: files[0].name, segments: [Self.addedSegment])
        }
        if Self.functionTargets.contains(target), functions.isEmpty {
            functions = [Function(name: 0, count: .value(1), files: [0], regions: [])]
        }
        if Self.regionTargets.contains(target), functions[0].regions.isEmpty {
            let first = functions[0]
            functions[0] = Function(
                name: first.name,
                count: first.count,
                files: first.files,
                regions: [Self.addedRegion]
            )
        }
        return Self(files: files, functions: functions, extraKeys: extraKeys, fault: fault)
    }

    /// Every count the document spells.
    var counts: [Count] {
        files.flatMap { $0.segments.map(\.count) }
            + functions.flatMap { [$0.count] + $0.regions.map(\.count) }
    }
}
