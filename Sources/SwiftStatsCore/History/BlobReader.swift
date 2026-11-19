//
//  BlobReader.swift
//  SwiftStatsCore
//
//  Reads many file versions from a repository with one
//  `git cat-file --batch` per batch of blobs, rather than one process per
//  file.
//

import Foundation

/// Reads blobs from a repository.
enum BlobReader {
    /// The fields of a `cat-file --batch` header line: name, type and size.
    private static let headerFieldCount = 3

    /// The contents of each blob in `blobs`, by blob name. A blob git can't
    /// read is left out.
    static func read(_ blobs: [String], top: URL) throws -> [String: Data] {
        guard blobs.isEmpty == false else {
            return [:]
        }
        let list = FileManager.default.temporaryDirectory
            .appendingPathComponent("SwiftStats-blobs-\(UUID().uuidString)")
        try Data((blobs.joined(separator: "\n") + "\n").utf8).write(to: list)
        defer { try? FileManager.default.removeItem(at: list) }
        let output = try ProcessRunner.run(
            executable: GitReader.git,
            arguments: ["--no-optional-locks", "cat-file", "--batch"],
            in: top,
            input: list
        )
        return parse(output)
    }

    /// The blobs in `cat-file --batch` output: for each, a header line
    /// `<name> blob <size>`, the content, and a newline.
    static func parse(_ output: Data) -> [String: Data] {
        var blobs: [String: Data] = [:]
        var position = output.startIndex
        let newline = UInt8(ascii: "\n")
        while position < output.endIndex {
            guard let lineEnd = output[position...].firstIndex(of: newline) else {
                break
            }
            let headerText = String(bytes: output[position..<lineEnd], encoding: .utf8) ?? ""
            let header = headerText.split(separator: " ")
            position = output.index(after: lineEnd)
            // `<name> missing` has no content.
            guard header.count == headerFieldCount, let size = Int(header.last ?? "") else {
                continue
            }
            let end = output.index(position, offsetBy: size, limitedBy: output.endIndex) ?? output.endIndex
            if header[1] == "blob" {
                blobs[String(header[0])] = Data(output[position..<end])
            }
            position = end < output.endIndex ? output.index(after: end) : output.endIndex
        }
        return blobs
    }
}
