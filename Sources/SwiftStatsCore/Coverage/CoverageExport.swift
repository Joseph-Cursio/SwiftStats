//
//  CoverageExport.swift
//  SwiftStatsCore
//
//  Reads `llvm-cov export`'s JSON (M5): it must be type
//  `llvm.coverage.json.export`, version 3.0.1, with one `data` element,
//  whose files and function entries are kept, each file's segments sorted
//  by line, then column (design B3, decided U6). Anything else fails the
//  coverage collector with a reason; one naming a file names it by the
//  export's real path, as the caller's `naming` writes it, so that the
//  collector can redact that path by its components.
//

import Foundation

/// The files and function entries of a coverage export.
struct CoverageExport: Decodable, Sendable {
    /// The keys read.
    private enum CodingKeys: String, CodingKey {
        case data, type, version
    }

    /// A file whose segments go back, found while decoding; its reason is
    /// written once the caller has named the file.
    private struct MisorderedFile: Error {
        /// The file's real path.
        let filename: String
        /// The segment the later one lies before.
        let earlier: CoverageSegment
        /// The segment that goes back.
        let later: CoverageSegment

        /// The reason, the file named by `name`.
        func failure(naming name: (String) -> String) -> CoverageFailure {
            CoverageFailure(
                description: "`llvm-cov export` wrote the segments of \(name(filename)) out of order "
                    + "(\(later.line):\(later.column) after \(earlier.line):\(earlier.column)); "
                    + "SwiftStats reads them sorted by line, then column"
            )
        }
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
    /// data; a `CoverageFailure` when they aren't, when there isn't
    /// exactly one data element, or when a file's segments go back.
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
        for file in payload.files {
            if let pair = file.misordered {
                throw MisorderedFile(filename: file.filename, earlier: pair.earlier, later: pair.later)
            }
        }
        files = payload.files
        functions = payload.functions
    }

    /// The export in `data`; a `CoverageFailure` when it isn't one this
    /// reads, a file it names written as found.
    static func decode(_ data: Data) throws -> Self {
        try decode(data) { $0 }
    }

    /// The export in `data`; a `CoverageFailure` when it isn't one this
    /// reads, a file it names written as `name` gives it.
    static func decode(_ data: Data, naming name: (String) -> String) throws -> Self {
        do {
            return try JSONDecoder().decode(Self.self, from: data)
        } catch let failure as CoverageFailure {
            throw failure
        } catch let misordered as MisorderedFile {
            throw misordered.failure(naming: name)
        } catch let error as DecodingError {
            throw CoverageFailure(description: "could not read `llvm-cov export`'s output: \(describe(error))")
        }
    }

    /// The export written to `url`, a file a failure names written as
    /// `name` gives it.
    static func read(_ url: URL, naming name: (String) -> String) throws -> Self {
        try decode(Data(contentsOf: url), naming: name)
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
