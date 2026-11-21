//
//  TestInventory.swift
//  SwiftStatsCore
//
//  Builds the test inventory (PRD §7.8): a test record for every function
//  record whose role is `test`, from the facts of its declaration, joined
//  on file and start position as complexity scores are; and, kept out of
//  the records, the base names each property test calls (§7.11), what
//  every test writes, and what every test helper writes (M5,
//  `TestReferences`). A helper is a function or initialiser of a test
//  target that is no test and isn't nested in another record. A nested
//  one's body is part of its parent's. Also kept out: each Swift Testing
//  test's identity and each target's `@Suite` types, which `--skip`
//  regexes match (`SwiftTestingIdentity`), and the typealiases each test target declares, which name the types
//  helpers are called on (`TestHelperExpansion`).
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
        /// What each test writes, by test key.
        let references: [String: TestReferences]
        /// What each test helper writes, its body and parameter clause, by
        /// helper key.
        let helperReferences: [String: TestReferences]
        /// Each Swift Testing test's identity, by test key.
        let identities: [String: SwiftTestingIdentity]
        /// The tags of each type declared `@Suite`, by its path's
        /// components, by test target.
        let suites: [String: [[String]: Set<String>]]
        /// The simple names of the types each typealias of a test target
        /// names, by alias, by target.
        let aliases: [String: [String: Set<String>]]
    }

    /// What the test targets' files declare, by where each declaration
    /// starts (`joinKey`), or by target.
    private struct Declarations {
        /// Each function's test facts.
        var facts: [String: TestFacts] = [:]
        /// Each Swift Testing test's identity.
        var identities: [String: SwiftTestingIdentity] = [:]
        /// Each function and initialiser.
        var declarations: [String: Syntax] = [:]
        /// The simple names of the types each typealias names, by alias,
        /// by target.
        var aliases: [String: [String: Set<String>]] = [:]
        /// The tags of each `@Suite` type, by its path, by target.
        var suites: [String: [[String]: Set<String>]] = [:]

        /// Adds what `file`, of the test target `module`, declares.
        mutating func add(_ file: ParsedFile, module: String) {
            let converter = SourceLocationConverter(fileName: file.path, tree: file.tree)
            let functions = FunctionFinder(viewMode: .sourceAccurate)
            functions.walk(file.tree)
            let location = { (node: Syntax) -> (line: Int, column: Int) in
                let location = converter.location(for: node.positionAfterSkippingLeadingTrivia)
                let offset = file.hasByteOrderMark && location.line == 1 ? ParsedFile.byteOrderMarkLength : 0
                return (location.line, location.column + offset)
            }
            let place = { (node: Syntax) -> String in
                let start = location(node)
                return joinKey(file.path, line: start.line, column: start.column)
            }
            for function in functions.found {
                let key = place(Syntax(function))
                facts[key] = TestFacts(function)
                identities[key] = SwiftTestingIdentity(function, location: location)
                declarations[key] = Syntax(function)
            }
            for initializer in functions.initializers {
                declarations[place(Syntax(initializer))] = Syntax(initializer)
            }
            for suite in functions.suites {
                suites[module, default: [:]][suite.path, default: []].formUnion(suite.tags)
            }
            for alias in functions.aliases {
                if let named = CallReferenceBuilder.path(of: alias.initializer.value).last {
                    aliases[module, default: [:]][CallSignature.name(of: alias.name), default: []].insert(named)
                }
            }
        }
    }

    /// A test record for each test among `records`, from the test targets'
    /// parsed files; the base names each property test calls, and what
    /// each test writes, by test key; and what each test helper writes, by
    /// helper key.
    static func inventory(
        records: [FunctionRecord],
        parsed: [(module: String, file: ParsedFile)],
        testModules: Set<String>,
        generatedFiles: Set<String>
    ) -> Inventory {
        var found = Declarations()
        for (module, file) in parsed where testModules.contains(module) {
            found.add(file, module: module)
        }
        var callees: [String: Set<String>] = [:]
        var references: [String: TestReferences] = [:]
        var testIdentities: [String: SwiftTestingIdentity] = [:]
        let tests = records.filter { $0.role == .test }.compactMap { record -> TestRecord? in
            let key = joinKey(record.file, line: record.range.start.line, column: record.range.start.column)
            guard let fact = found.facts[key] else {
                return nil
            }
            if fact.callees.isEmpty == false {
                callees[record.key] = fact.callees
            }
            references[record.key] = fact.references
            testIdentities[record.key] = found.identities[key]
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
        return Inventory(
            tests: tests,
            callees: callees,
            references: references,
            helperReferences: helperReferences(records: records, declarations: found.declarations),
            identities: testIdentities,
            suites: found.suites,
            aliases: found.aliases
        )
    }

    /// What each test helper among `records` writes, from its declaration
    /// among `declarations` (by `joinKey`), by helper key.
    private static func helperReferences(
        records: [FunctionRecord],
        declarations: [String: Syntax]
    ) -> [String: TestReferences] {
        var references: [String: TestReferences] = [:]
        for record in records where record.role == .helper && record.parentKey == nil {
            let key = joinKey(record.file, line: record.range.start.line, column: record.range.start.column)
            guard let declaration = declarations[key] else {
                continue
            }
            let scan = TestBodyScan(viewMode: .sourceAccurate)
            if let function = declaration.as(FunctionDeclSyntax.self) {
                scan.walk(function.signature.parameterClause)
                function.body.map { scan.walk($0) }
            } else if let initializer = declaration.as(InitializerDeclSyntax.self) {
                scan.walk(initializer.signature.parameterClause)
                initializer.body.map { scan.walk($0) }
            }
            references[record.key] = scan.references
        }
        return references
    }

    /// Where a declaration starts.
    private static func joinKey(_ file: String, line: Int, column: Int) -> String {
        "\(file)|\(line)|\(column)"
    }
}
