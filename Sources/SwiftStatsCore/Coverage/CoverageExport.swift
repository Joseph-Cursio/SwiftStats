//
//  CoverageExport.swift
//  SwiftStatsCore
//
//  Reads `llvm-cov export`'s JSON (M5): it must be type
//  `llvm.coverage.json.export`, version 3.0.1, with one `data` element,
//  whose files and function entries are kept. Anything else fails the
//  coverage collector with a reason.
//

import Foundation

/// The files and function entries of a coverage export.
struct CoverageExport: Decodable, Sendable {
    /// The keys read.
    private enum CodingKeys: String, CodingKey {
        case data, type, version
    }

    /// The one `data` element.
    private struct Payload: Decodable {
        /// The files.
        let files: [CoverageExportFile]
        /// The function entries.
        let functions: [CoverageExportFunction]
    }

    /// The type read.
    static let expectedType = "llvm.coverage.json.export"
    /// The version read.
    static let expectedVersion = "3.0.1"

    /// The files, sorted by path as the export writes them.
    let files: [CoverageExportFile]
    /// The function entries.
    let functions: [CoverageExportFunction]

    /// Decodes the type and version, then, when they are the ones read, the
    /// data; a `CoverageFailure` when they aren't, or when there isn't
    /// exactly one data element.
    init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let found = (
            type: try container.decode(String.self, forKey: .type),
            version: try container.decode(String.self, forKey: .version)
        )
        guard found.type == Self.expectedType, found.version == Self.expectedVersion else {
            throw CoverageFailure(
                description: "`llvm-cov export` wrote type \(found.type), version \(found.version); "
                    + "SwiftStats reads \(Self.expectedType) \(Self.expectedVersion)"
            )
        }
        let data = try container.decode([Payload].self, forKey: .data)
        guard data.count == 1, let payload = data.first else {
            throw CoverageFailure(
                description: "`llvm-cov export` wrote \(data.count) data elements; SwiftStats reads one"
            )
        }
        files = payload.files
        functions = payload.functions
    }

    /// The export in `data`; a `CoverageFailure` when it isn't one this
    /// reads.
    static func decode(_ data: Data) throws -> Self {
        do {
            return try JSONDecoder().decode(Self.self, from: data)
        } catch let failure as CoverageFailure {
            throw failure
        } catch let error as DecodingError {
            throw CoverageFailure(description: "could not read `llvm-cov export`'s output: \(describe(error))")
        }
    }

    /// The export written to `url`.
    static func read(_ url: URL) throws -> Self {
        try decode(Data(contentsOf: url))
    }

    /// `error` in one line: where in the document, and what.
    private static func describe(_ error: DecodingError) -> String {
        let context: DecodingError.Context
        switch error {
        case let .typeMismatch(_, found), let .valueNotFound(_, found), let .keyNotFound(_, found):
            context = found

        case .dataCorrupted(let found):
            context = found

        @unknown default:
            return "\(error)"
        }
        let path = context.codingPath.map { $0.intValue.map { "[\($0)]" } ?? ".\($0.stringValue)" }.joined()
        return (path.isEmpty ? "" : "at \(path): ") + context.debugDescription
    }
}
