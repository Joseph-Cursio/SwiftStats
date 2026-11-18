//
//  TestInventory.swift
//  SwiftStatsCore
//
//  Builds the test inventory (PRD §7.8): a test record for every function
//  record whose role is `test`, from the facts of its declaration, joined
//  on file and start position as complexity scores are.
//

import SwiftSyntax

/// Builds test records.
enum TestInventory {
    /// A test record for each test among `records`, from the test targets' parsed files.
    static func tests(
        records: [FunctionRecord],
        parsed: [(module: String, file: ParsedFile)],
        testModules: Set<String>,
        generatedFiles: Set<String>
    ) -> [TestRecord] {
        var facts: [String: TestFacts] = [:]
        for (module, file) in parsed where testModules.contains(module) {
            let converter = SourceLocationConverter(fileName: file.path, tree: file.tree)
            let functions = FunctionFinder(viewMode: .sourceAccurate)
            functions.walk(file.tree)
            for function in functions.found {
                let location = converter.location(for: function.positionAfterSkippingLeadingTrivia)
                let offset = file.hasByteOrderMark && location.line == 1 ? ParsedFile.byteOrderMarkLength : 0
                facts[joinKey(file.path, line: location.line, column: location.column + offset)] = TestFacts(function)
            }
        }
        return records.filter { $0.role == .test }.compactMap { record in
            let key = joinKey(record.file, line: record.range.start.line, column: record.range.start.column)
            guard let fact = facts[key] else {
                return nil
            }
            return TestRecord(
                key: record.key,
                module: record.module,
                file: record.file,
                framework: fact.framework,
                kind: fact.kind,
                cases: fact.cases,
                assertions: fact.assertions,
                trials: fact.trials,
                generated: generatedFiles.contains(record.file)
            )
        }
    }

    /// Where a declaration starts.
    private static func joinKey(_ file: String, line: Int, column: Int) -> String {
        "\(file)|\(line)|\(column)"
    }
}
