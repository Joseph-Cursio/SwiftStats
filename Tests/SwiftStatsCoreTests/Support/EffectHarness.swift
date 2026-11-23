//
//  EffectHarness.swift
//  SwiftStatsCoreTests
//
//  Runs the side-effect collector on the Effects fixture, or on source text,
//  as production files of module `Effects`.
//

import Foundation
import SwiftParser
@testable import SwiftStatsCore
import SwiftSyntax
import Testing

/// Parses files, collects their records and runs `EffectCollector`.
enum EffectHarness {
    /// The fixture package.
    static let fixture = URL(fileURLWithPath: #filePath)
        .deletingLastPathComponent()
        .deletingLastPathComponent()
        .deletingLastPathComponent()
        .appendingPathComponent("Fixtures/Effects")

    /// The fixture's source files, parsed, in path order.
    static func fixtureFiles() throws -> [ParsedFile] {
        let directory = fixture.appendingPathComponent("Sources/Effects")
        let names = try FileManager.default.contentsOfDirectory(atPath: directory.path)
            .filter { $0.hasSuffix(".swift") }
            .sorted()
        return try names.map { name in
            let source = try String(contentsOf: directory.appendingPathComponent(name), encoding: .utf8)
            return parsed(source, path: "Sources/Effects/\(name)")
        }
    }

    /// `source` parsed as the file at `path`, with no byte order mark.
    static func parsed(_ source: String, path: String) -> ParsedFile {
        ParsedFile(
            path: path,
            source: source,
            tree: Parser.parse(source: source),
            hasByteOrderMark: false,
            sha256: ContentHash.sha256(Data(source.utf8))
        )
    }

    /// The records of `files`, as production code of module `Effects`.
    static func records(of files: [ParsedFile]) -> [FunctionRecord] {
        files.flatMap { file in
            FunctionCollector.collect(file.tree, context: FileContext(
                module: "Effects",
                file: file.path,
                isTestTarget: false,
                testCaseClasses: [],
                converter: SourceLocationConverter(fileName: file.path, tree: file.tree),
                firstLineColumnOffset: file.hasByteOrderMark ? ParsedFile.byteOrderMarkLength : 0
            ))
        }
    }

    /// The collector's run over `files` and their records.
    static func run(_ files: [ParsedFile]) throws -> EffectRun {
        try EffectCollector.run(files: files, records: records(of: files))
    }

    /// The collector's run over the fixture.
    static func runFixture() throws -> EffectRun {
        try run(try fixtureFiles())
    }

    /// The collector's run over one file holding `source`.
    static func run(source: String) throws -> EffectRun {
        try run([parsed(source, path: "Sources/Effects/File.swift")])
    }

    /// The facts of the record keyed `key` in `run`.
    static func facts(_ key: String, in run: EffectRun) throws -> EffectFacts {
        try #require(run.facts[key], "no facts for \(key)")
    }

    /// The inferred tier of the function keyed `key` in `run`.
    static func inferred(_ key: String, in run: EffectRun) throws -> EffectFacts.Inferred {
        try #require(try facts(key, in: run).function?.inferred, "no inferred tier for \(key)")
    }
}
