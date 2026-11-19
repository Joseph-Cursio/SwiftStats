//
//  ReportCompression.swift
//  SwiftStatsCore
//
//  Raw DEFLATE (RFC 1951) for stored reports (PRD §9). Apple's `zlib`
//  algorithm writes raw DEFLATE, not a zlib stream, so the store names the
//  encoding `deflate` and records the uncompressed length to check against.
//

import Compression
import Foundation

/// Compresses and decompresses stored reports.
enum ReportCompression {
    /// The encoding name the store records.
    static let encoding = "deflate"
    /// How much decompressed data to read at a time.
    private static let pageSize = 1 << 16

    /// `data`, deflated.
    static func deflate(_ data: Data) throws -> Data {
        var output = Data()
        let filter = try OutputFilter(.compress, using: .zlib) { chunk in
            if let chunk {
                output.append(chunk)
            }
        }
        try filter.write(data)
        try filter.finalize()
        return output
    }

    /// `data` inflated, which must come to `length` bytes.
    static func inflate(_ data: Data, length: Int) throws -> Data {
        var offset = 0
        let filter = try InputFilter(.decompress, using: .zlib) { (wanted: Int) -> Data? in
            let end = min(offset + wanted, data.count)
            defer { offset = end }
            return data.subdata(in: offset..<end)
        }
        var output = Data()
        while let page = try filter.readData(ofLength: pageSize) {
            output.append(page)
        }
        guard output.count == length else {
            throw StoreError.corruptReport("expected \(length) bytes, got \(output.count)")
        }
        return output
    }
}
