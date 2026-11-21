//
//  TestInventory.swift
//  SwiftStatsCore
//
//  Builds the test inventory (PRD §7.8): a test record for every function
//  record whose role is `test`, from the facts of its declaration, joined
//  on file and start position as complexity scores are; and, kept out of
//  the records, the base names each property test calls (§7.11) and the
//  names every test's body refers to (M5).
//

import SwiftSyntax

/// Builds test records.
enum TestInventory {
    /// The inventory and what is kept out of its records.
    struct Inventory {
        /// A test record for each test.
        let tests: [TestRecord]
        /// The base names each property test calls, by test key.
        let callees: [String: Set<String>]
        /// The names each test refers to and calls, by test key.
        let references: [String: TestReferences]
    }

    /// A test record for each test among `records`, from the test targets'
    /// parsed files; the base names each property test calls, and the
    /// names each test refers to, by test key.
    static func inventory(
        records: [FunctionRecord],
        parsed: [(module: String, file: ParsedFile)],
        testModules: Set<String>,
        generatedFiles: Set<String>
    ) -> Inventory {
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
        var callees: [String: Set<String>] = [:]
        var references: [String: TestReferences] = [:]
        let tests = records.filter { $0.role == .test }.compactMap { record -> TestRecord? in
            let key = joinKey(record.file, line: record.range.start.line, column: record.range.start.column)
            guard let fact = facts[key] else {
                return nil
            }
            if fact.callees.isEmpty == false {
                callees[record.key] = fact.callees
            }
            references[record.key] = fact.references
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
        return Inventory(tests: tests, callees: callees, references: references)
    }

    /// Where a declaration starts.
    private static func joinKey(_ file: String, line: Int, column: Int) -> String {
        "\(file)|\(line)|\(column)"
    }
}
