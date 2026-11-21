//
//  CoverageTestLinks.swift
//  SwiftStatsCore
//
//  Tests per public function (M5, PRD §7.8). This is a heuristic, and it
//  is labelled as one. A test counts for a public function when two things
//  hold: its target's own test process ran the function, and the test
//  writes it. "The test" here includes its parameters, its `@Test`
//  arguments and the test helpers it calls (`TestHelperExpansion`). A test
//  that the coverage run's `--skip` regexes left out never counts
//  (`TestSkipFilter`).
//
//  A public function is a production, non-generated `public` or `open`
//  function, initialiser or accessor. A subscript counts too when it has
//  no accessor records; one with them counts through its accessors.
//
//  What writing it means depends on the function (`CoverageLink`):
//  - A function: a call whose argument labels fit its parameters
//    (`CallSignature`), or an unapplied reference written with all its
//    labels (`f(a:b:)`). A bare `f` or `x.f` with no labels doesn't count,
//    even for a function with no parameters.
//  - A free function: such a call bare or qualified by its module. A
//    member: such a call written on something (`x.f(…)`, `.f(…)`,
//    `T.f(…)`).
//  - An initialiser: a call of its type, `T(…)`, `T.init(…)`, `T<U>(…)`,
//    or an implicit `.init(…)` with an annotated binding, with labels that
//    fit. A qualified type (`A.T(…)`) must be qualified by a suffix of the
//    record's module and parent types (`TypePathMatch`).
//  - An accessor: a member read of its property (`x.name`, `.name`,
//    `T.name`, a key path component), never a bare identifier, which in a
//    test is a local, a parameter or the test's own member. A free
//    variable's accessor is linked by the bare identifier, or by the
//    module-qualified name. A member called with no argument labels
//    (`x.name()`) reads it too, since the property may hold a closure.
//  - A member of a concrete type also needs the test to name the type,
//    unqualified or qualified as above, or to sit in a test file named for
//    the member's file or type (`TestNameMatcher`). An initialiser's call
//    names its type.
//  - A protocol extension member is linked by its call or read alone.
//  - A subscript, or a protocol extension's initialiser or subscript, is
//    one whose name no body writes. It is linked by the test naming the
//    type or protocol, or by such a file.
//
//  Types are never read, so overloads that differ only in types (a
//  `Sequence` and a `Collection` extension's `f(by:)`, `Int?` and a range
//  parameter) each count every call of any of them; for generic libraries
//  this is the main error left.
//
//  Witnesses of standard protocols' requirements are reached generically
//  and get no count (`CoverageWitnesses`). Names are compared without the
//  backticks an escaped identifier is written with. Operators are never
//  names, so no operator function is ever linked.
//

/// Links public functions to the tests that write them.
struct CoverageTestLinks {
    /// The rule the report labels the counts with.
    static let rule = "heuristic: the test's target ran it and the test, or a test helper it calls, "
        + "calls it with fitting labels or reads it (a subscript: names its type)"
    /// The kinds of record that can be public functions.
    private static let kinds: Set<FunctionKind> = [.function, .initializer, .accessor, .subscriptDeclaration]

    /// The tests that weren't skipped, in inventory order.
    private let tests: [CoverageLinkTest]
    /// The tests that call each name, in order.
    private let byCall: [String: [Int]]
    /// The tests that read each name as a member, in order.
    private let byMember: [String: [Int]]
    /// The tests that write each path, in order.
    private let byPath: [String: [Int]]
    /// The tests of each test target, in order.
    private let byModule: [String: [Int]]
    /// Matches records' files and types to test files.
    private let matcher: TestNameMatcher
    /// Generated files.
    private let generated: Set<String>
    /// Keys of the subscripts whose accessors carry the coverage.
    private let containers: Set<String>
    /// Each file's function and initialiser records' parameters, by start.
    private let signatures: [String: [SourcePosition: CallSignature]]
    /// Tells protocols and witnesses apart.
    private let witnesses: CoverageWitnesses

    /// The links of `measured`'s public functions to its tests;
    /// `containers` are the subscripts whose accessors carry the coverage,
    /// and the tests `skipPatterns` (`--skip` regexes) match are left out.
    init(measured: ScanMeasurements, containers: Set<String>, skipPatterns: [String]) {
        let skip = TestSkipFilter(patterns: skipPatterns)
        let expansion = TestHelperExpansion(measured: measured)
        let records = Dictionary(measured.records.map { ($0.key, $0) }) { first, _ in first }
        tests = measured.tests.compactMap { test in
            // Every test record is built from the function record of its key.
            guard let record = records[test.key] else {
                return nil
            }
            let written = measured.testReferences[test.key] ?? .empty
            let signature = measured.signatures[record.file]?[record.range.start]
            let identity = measured.testIdentities[test.key]
            let suites = measured.testSuites[test.module] ?? [:]
            if skip.skips(test, record: record, signature: signature, identity: identity, suites: suites) {
                return nil
            }
            return CoverageLinkTest(
                module: test.module,
                testName: TestNameMatcher.testName(of: test.file),
                references: expansion.expanded(written, of: record)
            )
        }
        byCall = Self.index(tests) { $0.references.calls.map(\.name) }
        byMember = Self.index(tests) { $0.references.members }
        byPath = Self.index(tests) { $0.references.paths }
        byModule = Self.index(tests) { [$0.module] }
        matcher = TestNameMatcher(testFiles: measured.tests.map(\.file))
        generated = Set(measured.files.filter(\.generated).map(\.path))
        self.containers = containers
        signatures = measured.signatures
        witnesses = CoverageWitnesses(measured: measured)
    }

    /// The indices of `tests` under each key `keys` gives a test, in order,
    /// each once.
    private static func index(
        _ tests: [CoverageLinkTest],
        by keys: (CoverageLinkTest) -> some Sequence<String>
    ) -> [String: [Int]] {
        var index: [String: [Int]] = [:]
        for (position, test) in tests.enumerated() {
            for key in Set(keys(test)) {
                index[key, default: []].append(position)
            }
        }
        return index
    }

    /// The name tests write `record`'s type by: its last component, without
    /// backticks; empty at top level.
    private static func typeName(of record: FunctionRecord) -> String {
        record.typePath.map { TestReferences.unescaped(CoverageWitnesses.simpleName(of: $0)) } ?? ""
    }

    /// The rule `record`'s tests are counted by; nil when it isn't a
    /// public function.
    func link(of record: FunctionRecord) -> CoverageLink? {
        guard record.role == .production, record.access.isPublic, Self.kinds.contains(record.kind),
              generated.contains(record.file) == false, containers.contains(record.key) == false else {
            return nil
        }
        guard let typePath = record.typePath else {
            return .function
        }
        if witnesses.isProtocol(typePath, in: record.module) {
            return .extensionMember
        }
        if witnesses.isWitness(record, of: typePath) {
            return .witness
        }
        return isSubscript(record) ? .subscript : .member
    }

    /// How many tests of `targets`, the test targets that ran `record`,
    /// write it by `link`; nil for a witness.
    func linkedTests(of record: FunctionRecord, link: CoverageLink, targets: [String]) -> Int? {
        let ran = Set(targets)
        let typeName = Self.typeName(of: record)
        let allowed = TypePathMatch.allowedQualifiers(module: record.module, path: record.typePath ?? "")
        switch link {
        case .witness:
            return nil

        case .extensionMember where record.kind == .initializer || isSubscript(record):
            return typeNamed(record, typeName: typeName, allowed: allowed, targets: targets)

        case .subscript:
            return typeNamed(record, typeName: typeName, allowed: allowed, targets: targets)

        case .function, .extensionMember, .member:
            let files = link == .member ? matcher.matches(file: record.file, typeName: typeName) : []
            return candidates(of: record, link: link, typeName: typeName).count { index in
                let test = tests[index]
                guard ran.contains(test.module), writes(record, link: link, in: test, allowed: allowed) else {
                    return false
                }
                return link != .member || record.kind == .initializer
                    || test.namesType(typeName, within: allowed) || files.contains(test.testName)
            }
        }
    }

    /// The tests that may write `record`, a function, initialiser or
    /// accessor linked by `link`, in order.
    private func candidates(of record: FunctionRecord, link: CoverageLink, typeName: String) -> [Int] {
        let name = TestReferences.unescaped(record.name)
        switch record.kind {
        case .initializer:
            return byCall[typeName] ?? []

        case .accessor where link == .function:
            let qualified = CoverageBundles.moduleName(of: record.module) + "." + name
            let either = Set((byPath[name] ?? []) + (byPath[qualified] ?? []))
            return either.sorted()

        case .accessor:
            return byMember[name] ?? []

        default:
            return byCall[name] ?? []
        }
    }

    /// Whether `test` writes `record`, linked by `link`: a call with
    /// fitting labels of a function or initialiser, a read of an accessor's
    /// property (`allowed` qualifies an initialiser's type).
    private func writes(
        _ record: FunctionRecord,
        link: CoverageLink,
        in test: CoverageLinkTest,
        allowed: [String]
    ) -> Bool {
        let name = TestReferences.unescaped(record.name)
        let references = test.references
        let module = CoverageBundles.moduleName(of: record.module)
        if record.kind == .accessor {
            guard link == .function else {
                return references.members.contains(name)
            }
            return references.paths.contains(name) || references.paths.contains(module + "." + name)
        }
        guard let signature = signatures[record.file]?[record.range.start] else {
            return false
        }
        if record.kind == .initializer {
            let typeName = Self.typeName(of: record)
            return test.calls(of: typeName).contains { call in
                call.isQualified(within: allowed) && call.fits(signature)
            }
        }
        return test.calls(of: name).contains { call in
            guard call.isInitializer == false else {
                return false
            }
            let placed = link == .function
                ? call.receiver == .bare || call.receiver == .path([module])
                : call.isMember
            return placed && call.fits(signature)
        }
    }

    /// How many tests of `targets` name `typeName`, `record`'s type,
    /// unqualified or by a suffix of `allowed`, or sit in a file named for
    /// `record`'s file or type: the rule for a function whose name no body
    /// writes.
    private func typeNamed(_ record: FunctionRecord, typeName: String, allowed: [String], targets: [String]) -> Int {
        let files = matcher.matches(file: record.file, typeName: typeName)
        return targets.reduce(0) { total, target in
            total + (byModule[target] ?? []).count { index in
                tests[index].namesType(typeName, within: allowed) || files.contains(tests[index].testName)
            }
        }
    }

    /// Whether `record` is a subscript or one of a subscript's accessors.
    private func isSubscript(_ record: FunctionRecord) -> Bool {
        record.kind == .subscriptDeclaration || (record.kind == .accessor && record.name == "subscript")
    }
}
