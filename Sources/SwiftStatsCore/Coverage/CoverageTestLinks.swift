//
//  CoverageTestLinks.swift
//  SwiftStatsCore
//
//  Tests per public function (M5, PRD §7.8), a heuristic labelled as one:
//  a test counts for a public function when its target's own test process
//  ran the function and its body names it. A public function is a
//  production, non-generated `public` or `open` function, initialiser or
//  accessor, or a subscript with no accessor records (one with them counts
//  through its accessors). What naming means depends on the function
//  (`CoverageLink`): a free function or a protocol extension member by its
//  base name; a member of a concrete type by its name (its property's for
//  an accessor, a call of the type for an initialiser) together with the
//  type's simple name, or a test file named for the member's file or type
//  (`TestNameMatcher`); a subscript, or a protocol extension's initialiser
//  or subscript, whose names no body writes, by the type's or protocol's
//  name or such a file. A type path names a protocol unless the record's
//  module declares a concrete type of that path. A member witnessing a
//  requirement of a standard protocol its type declares a conformance to
//  anywhere in the module (`StandardProtocols`, decided from syntax), or
//  inherits one from a superclass the module declares, is reached
//  generically, and no tests are counted for it; a conformance is read in
//  the module first, then across the package. Names are compared without
//  the backticks an escaped identifier is written with. Operators are
//  never names, so no operator function is ever linked.
//

/// Links public functions to the tests that name them.
struct CoverageTestLinks {
    /// One test, as the links read it.
    private struct Test {
        /// Its test target.
        let module: String
        /// Its file's test name (`TestNameMatcher.testName(of:)`).
        let testName: String
        /// What its body names.
        let references: TestReferences
    }

    /// A type, as its member records name it.
    private struct TypeIdentity: Hashable {
        /// Its module.
        let module: String
        /// Its type path.
        let path: String
    }

    /// The rule the report labels the counts with.
    static let rule = "heuristic: the test's target ran it and its body names it"
    /// The kinds of record that can be public functions.
    private static let kinds: Set<FunctionKind> = [.function, .initializer, .accessor, .subscriptDeclaration]

    /// The tests, in inventory order.
    private let tests: [Test]
    /// The tests whose body names each name, in order.
    private let byName: [String: [Int]]
    /// The tests whose body calls each name, in order.
    private let byCall: [String: [Int]]
    /// The tests of each test target, in order.
    private let byModule: [String: [Int]]
    /// Matches records' files and types to test files.
    private let matcher: TestNameMatcher
    /// Generated files.
    private let generated: Set<String>
    /// Keys of the subscripts whose accessors carry the coverage.
    private let containers: Set<String>
    /// Each file's member selectors, by record start.
    private let selectors: [String: [SourcePosition: String]]
    /// Each type's declaration and extension records.
    private let typeRecords: [TypeIdentity: [TypeRecord]]
    /// Each module's protocols and what each refines.
    private let protocols: [TypeIdentity: [String]]
    /// The package's protocols by path, and what each refines in any module.
    private let protocolPaths: [String: [String]]
    /// Each module's structs, classes, enums and actors.
    private let concreteTypes: Set<TypeIdentity>
    /// The paths of the package's structs, classes, enums and actors.
    private let concretePaths: Set<String>

    /// The links of `measured`'s public functions to its tests;
    /// `containers` are the subscripts whose accessors carry the coverage.
    init(measured: ScanMeasurements, containers: Set<String>) {
        tests = measured.tests.map { test in
            Test(
                module: test.module,
                testName: TestNameMatcher.testName(of: test.file),
                references: measured.testReferences[test.key] ?? TestReferences(names: [], calls: [])
            )
        }
        byName = Self.index(tests) { $0.references.names }
        byCall = Self.index(tests) { $0.references.calls }
        byModule = Self.index(tests) { [$0.module] }
        matcher = TestNameMatcher(testFiles: measured.tests.map(\.file))
        generated = Set(measured.files.filter(\.generated).map(\.path))
        self.containers = containers
        selectors = measured.selectors
        typeRecords = Dictionary(grouping: measured.types.filter { $0.isLocal == false }) { type in
            TypeIdentity(module: type.module, path: type.name)
        }
        let declaredProtocols = measured.types.filter { $0.kind == .protocolType && $0.isLocal == false }
        protocols = Dictionary(grouping: declaredProtocols) { TypeIdentity(module: $0.module, path: $0.name) }
            .mapValues { $0.flatMap(\.conformances) }
        protocolPaths = Dictionary(grouping: declaredProtocols, by: \.name).mapValues { $0.flatMap(\.conformances) }
        let concrete = measured.types.filter { type in
            type.isLocal == false && type.kind != .protocolType && type.kind != .extensionDeclaration
        }
        concreteTypes = Set(concrete.map { TypeIdentity(module: $0.module, path: $0.name) })
        concretePaths = Set(concrete.map(\.name))
    }

    /// The indices of `tests` under each key `keys` gives a test, in order.
    private static func index(_ tests: [Test], by keys: (Test) -> some Sequence<String>) -> [String: [Int]] {
        var index: [String: [Int]] = [:]
        for (position, test) in tests.enumerated() {
            for key in keys(test) {
                index[key, default: []].append(position)
            }
        }
        return index
    }

    /// The last component of a type path.
    private static func simpleName(of path: String) -> String {
        path.split(separator: ".").last.map(String.init) ?? path
    }

    /// The name tests write `record`'s type by: its last component, without
    /// backticks; empty at top level.
    private static func typeName(of record: FunctionRecord) -> String {
        record.typePath.map { TestReferences.unescaped(simpleName(of: $0)) } ?? ""
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
        if isProtocol(typePath, in: record.module) {
            return .extensionMember
        }
        if isWitness(record, of: typePath) {
            return .witness
        }
        return isSubscript(record) ? .subscript : .member
    }

    /// How many tests of `targets`, the test targets that ran `record`,
    /// name it by `link`; nil for a witness.
    func linkedTests(of record: FunctionRecord, link: CoverageLink, targets: [String]) -> Int? {
        let ran = Set(targets)
        let typeName = Self.typeName(of: record)
        let name = TestReferences.unescaped(record.name)
        switch link {
        case .witness:
            return nil

        case .extensionMember where record.kind == .initializer || isSubscript(record):
            return typeNamed(record, typeName: typeName, targets: targets)

        case .function, .extensionMember:
            return (byName[name] ?? []).count { ran.contains(tests[$0].module) }

        case .member:
            let named = record.kind == .initializer ? byCall[typeName] : byName[name]
            let files = matcher.matches(file: record.file, typeName: typeName)
            return (named ?? []).count { index in
                ran.contains(tests[index].module) && names(typeName, inTest: index, orFileIn: files)
            }

        case .subscript:
            return typeNamed(record, typeName: typeName, targets: targets)
        }
    }

    /// How many tests of `targets` name `typeName`, `record`'s type, or
    /// sit in a file named for `record`'s file or type: the rule for a
    /// function whose name no body writes.
    private func typeNamed(_ record: FunctionRecord, typeName: String, targets: [String]) -> Int {
        let files = matcher.matches(file: record.file, typeName: typeName)
        return targets.reduce(0) { total, target in
            total + (byModule[target] ?? []).count { names(typeName, inTest: $0, orFileIn: files) }
        }
    }

    /// Whether test `index` names `typeName`, or its file's test name is
    /// among `files`.
    private func names(_ typeName: String, inTest index: Int, orFileIn files: Set<String>) -> Bool {
        tests[index].references.names.contains(typeName) || files.contains(tests[index].testName)
    }

    /// Whether `path`, as `module` writes it, names a protocol: not when
    /// `module` declares a concrete type of that path; otherwise one the
    /// package declares, or a standard one the package declares no type of
    /// that name for.
    private func isProtocol(_ path: String, in module: String) -> Bool {
        if concreteTypes.contains(TypeIdentity(module: module, path: path)) {
            return false
        }
        if protocolPaths[path] != nil {
            return true
        }
        return concretePaths.contains(path) == false && StandardProtocols.names.contains(Self.simpleName(of: path))
    }

    /// What a type conforming to `name`, as `module` writes it, conforms to
    /// through it: when `module` declares a concrete type of that name (a
    /// superclass), what that type's declarations and extensions conform
    /// to, which its subclasses inherit; otherwise what the protocol
    /// refines, `module`'s own protocol of that name, or else any module's.
    private func refinements(of name: String, in module: String) -> [String] {
        let identity = TypeIdentity(module: module, path: name)
        if concreteTypes.contains(identity) {
            return (typeRecords[identity] ?? []).flatMap(\.conformances)
        }
        return protocols[identity] ?? protocolPaths[name] ?? []
    }

    /// Whether `record` is a subscript or one of a subscript's accessors.
    private func isSubscript(_ record: FunctionRecord) -> Bool {
        record.kind == .subscriptDeclaration || (record.kind == .accessor && record.name == "subscript")
    }

    /// Whether `record`, a member of the type at `path`, matches a
    /// requirement of a standard protocol its type conforms to, as the
    /// declarations and extensions of the type in the module write it (in
    /// the record's file only for a file-scoped type), refinements, the
    /// package's own protocols and the module's superclasses followed.
    private func isWitness(_ record: FunctionRecord, of path: String) -> Bool {
        guard let selector = selectors[record.file]?[record.range.start] else {
            return false
        }
        let declared = (typeRecords[TypeIdentity(module: record.module, path: path)] ?? [])
            .filter { record.typeFile == nil || $0.file == record.typeFile }
            .flatMap(\.conformances)
        var pending = declared
        var seen = Set<String>()
        while let name = pending.popLast() {
            guard seen.insert(name).inserted else {
                continue
            }
            if StandardProtocols.requirements[name]?.contains(selector) == true {
                return true
            }
            pending += StandardProtocols.refinements[name] ?? []
            pending += refinements(of: name, in: record.module)
        }
        return false
    }
}
