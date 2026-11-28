//
//  ExportDraft+Document.swift
//  SwiftStatsCoreTests
//
//  The document an `ExportDraft` makes, and what decoding it should give.
//  The document is built as `JSONText`, with the draft's fault written in:
//  a member left out, a value of the wrong type, a row one element short,
//  a count spelled out of range, a segment going back appended to the
//  last file; then cut short or one byte changed. Each count reads as
//  `CoverageCount` documents: as spelled within `Int64`, `Int64.max` past
//  it up to `UInt64.max`, and a decoding failure past that or below
//  `Int64.min`. The reasons are the decoder's (PRD §7.8).
//

import Foundation
@testable import SwiftStatsCore

/// The document an export draft makes.
extension ExportDraft {
    /// The type the decoder reads.
    static let type = CoverageExport.expectedType
    /// The version it reads.
    static let version = CoverageExport.expectedVersion
    /// What a value of the wrong type is, by the key or field it is under.
    static let mistypings: [String: JSONText] = [
        "count": .string("5"),
        "data": .object([]),
        "filename": .integer(0),
        "filenames": .string("a"),
        "files": .string("x"),
        "functions": .bool(true),
        "name": .array([]),
        "regionKind": .bool(true),
        "regions": .integer(1),
        "segmentFlag": .string("true"),
        "segmentLine": .string("3"),
        "segments": .object([]),
        "type": .integer(1),
        "version": .array([])
    ]

    /// The bytes of the document, its fault written in.
    var data: Data {
        let draft = normalized
        var bytes = Array(draft.document.text.utf8)
        switch draft.fault {
        case let .badByte(offset, byte):
            bytes[offset % bytes.count] = byte

        case .truncated(let offset):
            bytes = Array(bytes.prefix(offset % bytes.count))

        default:
            break
        }
        return Data(bytes)
    }

    /// The document as JSON, before a byte is changed or the text cut.
    var document: JSONText {
        let payload = JSONText.object(
            [
                member(
                    "files",
                    .array(files.enumerated().map { index, file in
                        fileObject(file, isFirst: index == 0, isLast: index == files.count - 1)
                    }),
                    applies: true
                ),
                member(
                    "functions",
                    .array(functions.enumerated().map { functionObject($0.element, isFirst: $0.offset == 0) }),
                    applies: true
                ),
                member("totals", .object([]), applies: true)
            ]
            .compactMap(\.self)
        )
        var elements = [payload]
        if case .dataCount(let count) = fault {
            elements = Array(repeating: payload, count: count)
        }
        var typeValue = JSONText.string(Self.type)
        var versionValue = JSONText.string(Self.version)
        if case .wrongType(let found) = fault {
            typeValue = .string(found)
        }
        if case .wrongVersion(let found) = fault {
            versionValue = .string(found)
        }
        let members = [
            member("data", .array(elements), applies: true),
            member("type", typeValue, applies: true),
            member("version", versionValue, applies: true)
        ]
        return .object(members.compactMap(\.self))
    }

    /// The segment the misordered fault appends to `positions`: on the
    /// last one's line, one column before it.
    static func backward(after positions: [SourcePosition]) -> SourcePosition {
        let last = positions.last ?? SourcePosition(line: 1, column: 1)
        return SourcePosition(line: last.line, column: last.column - 1)
    }

    /// A file's segments as the decoder reads them, before any fault is
    /// written in.
    func positions(of file: File) -> [SourcePosition] {
        var positions: [SourcePosition] = []
        for segment in file.segments {
            let last = positions.last ?? SourcePosition(line: 1, column: 1)
            positions.append(
                segment.lineStep == 0 && positions.isEmpty == false
                    ? SourcePosition(line: last.line, column: last.column + segment.columnStep)
                    : SourcePosition(line: last.line + segment.lineStep, column: 1 + segment.columnStep)
            )
        }
        return positions
    }

    /// `key` and `value` as a member, `value` mistyped or the member left
    /// out when the fault is about `key` and `applies`.
    func member(_ key: String, _ value: JSONText, applies: Bool) -> JSONText.Member? {
        guard applies else {
            return JSONText.Member(key: key, value: value)
        }
        switch fault {
        case .missing(key):
            return nil

        case .mistyped(key):
            return JSONText.Member(key: key, value: Self.mistypings[key] ?? value)

        default:
            return JSONText.Member(key: key, value: value)
        }
    }

    /// `count` as spelled, or out of range when the fault is about
    /// `target` and `applies`.
    func spelled(_ count: Count, target: String, applies: Bool) -> JSONText {
        if applies, case .outOfRange(target, let spelling) = fault {
            return .number(spelling)
        }
        switch count {
        case .clamped(let value):
            return .integer(value)

        case .spelled(let spelling):
            return .number(spelling)

        case .value(let value):
            return .integer(value)
        }
    }

    /// The elements `row` holds, one short when the fault is a short row
    /// of `kind` and `applies`.
    func row(_ row: [JSONText], kind: String, extras: Int, applies: Bool) -> JSONText {
        if applies, fault == .shortRow(kind) {
            return .array(Array(row.dropLast()))
        }
        return .array(row + Array(repeating: .integer(0), count: extras))
    }

    /// `file` as an object; the fault applies to it when `isFirst`, but a
    /// segment going back when `isLast`.
    func fileObject(_ file: File, isFirst: Bool, isLast: Bool) -> JSONText {
        var rows = zip(file.segments, positions(of: file)).enumerated().map { index, pair in
            segmentRow(pair.0, at: pair.1, applies: isFirst && index == 0)
        }
        if isLast, fault == .misordered {
            let back = Self.backward(after: positions(of: file))
            rows.append(.array([
                .integer(back.line), .integer(back.column), .integer(1), .bool(true), .bool(true), .bool(false)
            ]))
        }
        let extra = extraKeys
            ? [
                member("branches", .array([]), applies: false),
                member("expansions", .array([]), applies: false),
                member("summary", .object([JSONText.Member(key: "lines", value: .object([]))]), applies: false)
            ]
            : []
        let members = [
            member("filename", .string(CoverageExportGen.filenames[file.name]), applies: isFirst),
            member("segments", .array(rows), applies: isFirst)
        ]
        return .object((members + extra).compactMap(\.self))
    }

    /// `segment` at `position` as a row; the fault applies to it when
    /// `applies`.
    func segmentRow(_ segment: Segment, at position: SourcePosition, applies: Bool) -> JSONText {
        let line = applies && fault == .mistyped("segmentLine")
            ? Self.mistypings["segmentLine"] ?? .integer(position.line)
            : .integer(position.line)
        let flag = applies && fault == .mistyped("segmentFlag")
            ? Self.mistypings["segmentFlag"] ?? .bool(segment.hasCount)
            : .bool(segment.hasCount)
        return row(
            [
                line, .integer(position.column), spelled(segment.count, target: "segment", applies: applies), flag,
                .bool(segment.isRegionEntry), .bool(segment.isGapRegion)
            ],
            kind: "segment",
            extras: segment.extras,
            applies: applies
        )
    }

    /// `function` as an object; the fault applies to it when `isFirst`.
    func functionObject(_ function: Function, isFirst: Bool) -> JSONText {
        let regions = function.regions.enumerated().map { index, region in
            regionRow(region, applies: isFirst && index == 0)
        }
        let extra = extraKeys
            ? [member("branches", .array([]), applies: false), member("mcdc_records", .array([]), applies: false)]
            : []
        return .object(
            ([
                member("count", spelled(function.count, target: "function", applies: isFirst), applies: isFirst),
                member(
                    "filenames",
                    .array(function.files.map { .string(CoverageExportGen.filenames[$0]) }),
                    applies: isFirst
                ),
                member("name", .string(CoverageExportGen.functionNames[function.name]), applies: isFirst),
                member("regions", .array(regions), applies: isFirst)
            ] + extra)
                .compactMap(\.self)
        )
    }

    /// `region` as a row; the fault applies to it when `applies`.
    func regionRow(_ region: Region, applies: Bool) -> JSONText {
        let kind = applies && fault == .mistyped("regionKind")
            ? Self.mistypings["regionKind"] ?? .integer(region.kind)
            : .integer(region.kind)
        return row(
            [
                .integer(region.start.line), .integer(region.start.column), .integer(region.end.line),
                .integer(region.end.column), spelled(region.count, target: "region", applies: applies),
                .integer(region.fileID), .integer(0), kind
            ],
            kind: "region",
            extras: region.extras,
            applies: applies
        )
    }
}
