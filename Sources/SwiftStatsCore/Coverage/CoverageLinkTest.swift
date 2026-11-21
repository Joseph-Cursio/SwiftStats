//
//  CoverageLinkTest.swift
//  SwiftStatsCore
//
//  One test as tests per public function read it (M5): its target, its
//  file's test name, and what it writes, together with what the test
//  helpers it calls write (`TestHelperExpansion`). The types it names are
//  indexed by simple name, each with the qualifiers it was written with.
//

/// One test, as the links read it.
struct CoverageLinkTest {
    /// Its test target.
    let module: String
    /// Its file's test name (`TestNameMatcher.testName(of:)`).
    let testName: String
    /// What it and the helpers it calls write.
    let references: TestReferences
    /// The qualifiers each simple name is written with (`A.B` gives `B`
    /// written with `["A"]`, and `A` with `[]`).
    private let qualifiers: [String: [[String]]]
    /// The calls of each name.
    private let callsByName: [String: [CallReference]]

    /// A test of `module` in a file whose test name is `testName`, writing
    /// `references`.
    init(module: String, testName: String, references: TestReferences) {
        self.module = module
        self.testName = testName
        self.references = references
        var bySimpleName: [String: [[String]]] = [:]
        for path in references.paths {
            let components = path.split(separator: ".").map(String.init)
            if let last = components.last {
                bySimpleName[last, default: []].append(Array(components.dropLast()))
            }
        }
        qualifiers = bySimpleName
        callsByName = Dictionary(grouping: references.calls, by: \.name)
    }

    /// The calls it writes of `name`.
    func calls(of name: String) -> [CallReference] {
        callsByName[name] ?? []
    }

    /// Whether it names a type whose simple name is `simpleName`,
    /// unqualified or by a suffix of `allowed` (`TypePathMatch`).
    func namesType(_ simpleName: String, within allowed: [String]) -> Bool {
        (qualifiers[simpleName] ?? []).contains { TypePathMatch.isSuffix($0, of: allowed) }
    }
}
