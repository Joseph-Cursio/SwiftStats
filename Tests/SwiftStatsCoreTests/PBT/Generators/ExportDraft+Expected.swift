//
//  ExportDraft+Expected.swift
//  SwiftStatsCoreTests
//
//  What decoding an `ExportDraft`'s document should give, from the
//  decoder's documented reading (PRD §7.8, `CoverageExport`'s and
//  `CoverageCount`'s doc comments): a document of the type and version it
//  reads, with one data element, every row and member it reads well
//  typed, every count within `UInt64` and none below `Int64.min`, and
//  every file's segments sorted, decodes to its files and entries, each
//  count as spelled, or `Int64.max` past it; extra row elements and
//  members are ignored. Otherwise it fails with the reason for the first
//  check it fails, in the decoder's order: the type and version must
//  decode, then be the ones read; then the data must decode, then hold
//  one element; then each file's segments must not go back. A changed
//  byte, or a count whose spelling isn't labelled, may give anything but a
//  trap or another error.
//

@testable import SwiftStatsCore

/// What decoding an export draft's document should give.
extension ExportDraft {
    /// What decoding the document should give.
    var expected: Expected {
        let draft = normalized
        let spelled = draft.counts.contains { count in
            guard case .spelled = count else {
                return false
            }
            return true
        }
        guard spelled == false else {
            return .unknown
        }
        return draft.outcome
    }

    /// What decoding the document of this draft, normalized, with no
    /// unlabelled spelling, should give.
    private var outcome: Expected {
        switch fault {
        case .badByte:
            return .unknown

        case .dataCount(let count):
            return .refused("`llvm-cov export` wrote \(count) data elements; SwiftStats reads one")

        case .misordered:
            let positions = positions(of: files[0])
            let back = Self.backward(after: positions)
            let last = positions.last ?? back
            return .refused(
                "`llvm-cov export` wrote the segments of \(CoverageExportGen.filenames[files[0].name]) out of order "
                    + "(\(back.line):\(back.column) after \(last.line):\(last.column)); "
                    + "SwiftStats reads them sorted by line, then column"
            )

        case .missing, .mistyped, .outOfRange, .shortRow, .truncated:
            return .unreadable

        case .sound:
            return .accepted(files: files.map(read), functions: functions.map(read))

        case .wrongType(let found):
            return .refused(Self.formatReason(type: found, version: Self.version))

        case .wrongVersion(let found):
            return .refused(Self.formatReason(type: Self.type, version: found))
        }
    }

    /// The reason a document of `type` and `version` isn't read.
    static func formatReason(type: String, version: String) -> String {
        "`llvm-cov export` wrote type \(type), version \(version); SwiftStats reads \(Self.type) \(Self.version)"
    }

    /// `count` as read: as spelled, or `Int64.max` past it.
    static func read(_ count: Count) -> Int64 {
        switch count {
        case .clamped:
            return Int64.max

        case .spelled:
            return 0

        case .value(let value):
            return value
        }
    }

    /// `file` as read.
    func read(_ file: File) -> CoverageExportFile {
        CoverageExportFile(
            filename: CoverageExportGen.filenames[file.name],
            segments: zip(file.segments, positions(of: file)).map { segment, position in
                CoverageSegment(
                    line: position.line,
                    column: position.column,
                    executionCount: Self.read(segment.count),
                    hasCount: segment.hasCount,
                    isRegionEntry: segment.isRegionEntry,
                    isGapRegion: segment.isGapRegion
                )
            }
        )
    }

    /// `function` as read.
    func read(_ function: Function) -> CoverageExportFunction {
        CoverageExportFunction(
            name: CoverageExportGen.functionNames[function.name],
            count: Self.read(function.count),
            filenames: function.files.map { CoverageExportGen.filenames[$0] },
            regions: function.regions.map { region in
                CoverageRegion(
                    start: region.start,
                    end: region.end,
                    executionCount: Self.read(region.count),
                    fileID: region.fileID,
                    expandedFileID: 0,
                    kind: region.kind
                )
            }
        )
    }
}
