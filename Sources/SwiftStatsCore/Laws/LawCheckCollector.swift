//
//  LawCheckCollector.swift
//  SwiftStatsCore
//
//  Law detection (PRD §7.11), a `swiftstats` measurement run in the
//  measure step. Subjects are production structs, classes, enums and
//  actors outside function bodies; each pair is a kit protocol a subject
//  conforms to. A pair's state is the first that applies: suppressed by a
//  marker in the discovery plugin's file; run by a test-target
//  `check<P>PropertyLaws` call (which also runs what P inherits, unless
//  `laws: .ownOnly`; a check on a type local to the test attaches nowhere,
//  and one on a generic parameter or associated type is unresolved); run
//  by `@PropertyLawSuite` on a primary declaration, which reads its
//  inheritance clause exactly as written; waived by a running
//  floating-point check; otherwise not run.
//

/// Detects law checks per production conformance.
enum LawCheckCollector {
    /// What the package's tests and generated files check, per type.
    private struct Coverage {
        /// Protocols whose checks a test calls, per type.
        var called: [LawTypeResolver.TypeName: Set<String>] = [:]
        /// Protocols a suppression marker replaces, per type.
        var suppressed: [LawTypeResolver.TypeName: Set<String>] = [:]
        /// Checks whose subject can't be named.
        var unresolvedCalls = 0
        /// Names that resolved to more than one type.
        var ambiguousNames: Set<String> = []
    }

    /// The law checks of the files in `unsorted`, which may come in any
    /// order, with `generatedFiles` the paths of generated files.
    /// `kitDependency` is left false: the scan sets it from the package's
    /// dependencies.
    static func detect(_ unsorted: [LawFileFacts], generatedFiles: Set<String>) -> LawReport {
        let files = unsorted.sorted { $0.file < $1.file }
        let resolver = LawTypeResolver(files)
        let protocolNames = files.flatMap { file in
            file.declarations.filter { $0.kind == .protocolType }.map { declaration in
                declaration.name.split(separator: ".").last.map(String.init) ?? declaration.name
            }
        }
        let blocked = KitProtocols.algebraic.intersection(protocolNames)
        let (subjects, testSites) = subjects(of: files, resolver: resolver)
        let coverage = coverage(of: files, resolver: resolver)
        var checks: [LawCheck] = []
        var testOnly = 0
        for subject in subjects.values {
            let pairs = subject.pairs(blocked: blocked)
            checks += pairs.map { pair in
                check(pair, of: subject, coverage: coverage, generatedFiles: generatedFiles)
            }
            if let sites = testSites[subject.type] {
                let declared = Set(pairs.map(\.protocolName))
                let testPairs = LawSubject(type: subject.type, extensions: sites).pairs(blocked: blocked)
                testOnly += Set(testPairs.map(\.protocolName)).subtracting(declared).count
            }
        }
        return LawReport(
            checks: checks.sorted { ($0.type, $0.protocolName) < ($1.type, $1.protocolName) },
            unresolvedCalls: coverage.unresolvedCalls,
            ambiguousNames: coverage.ambiguousNames.sorted(),
            testOnlyConformances: testOnly,
            kitDependency: false
        )
    }

    /// The production subjects, with their primaries and production
    /// extensions, and the test-target extensions resolving to each.
    private static func subjects(
        of files: [LawFileFacts],
        resolver: LawTypeResolver
    ) -> ([LawTypeResolver.TypeName: LawSubject], [LawTypeResolver.TypeName: [LawSubject.Site]]) {
        let subjectKinds: Set<TypeKind> = [.structType, .classType, .enumType, .actor]
        var subjects: [LawTypeResolver.TypeName: LawSubject] = [:]
        for file in files where file.isTest == false {
            for declaration in file.declarations where subjectKinds.contains(declaration.kind) {
                let type = LawTypeResolver.TypeName(declaration, in: file)
                let site = LawSubject.Site(declaration, in: file)
                subjects[type, default: LawSubject(type: type)].primaries.append(site)
            }
        }
        for file in files where file.isTest == false {
            for witness in file.operatorWitnesses {
                if case .resolved(let type) = resolver.resolve(
                    witness.typeName,
                    in: file.module,
                    file: file.file,
                    scope: []
                ) {
                    subjects[type]?.operators.append(LawSubject.Operator(
                        witness: witness.witness,
                        module: file.module,
                        file: file.file,
                        fileScoped: witness.fileScoped
                    ))
                }
            }
        }
        var testSites: [LawTypeResolver.TypeName: [LawSubject.Site]] = [:]
        for file in files {
            for declaration in file.declarations where declaration.kind == .extensionDeclaration {
                guard case .resolved(let type) = resolver.resolve(
                    declaration.name,
                    in: file.module,
                    file: file.file,
                    scope: []
                ), subjects[type] != nil else {
                    continue
                }
                let site = LawSubject.Site(declaration, in: file)
                if file.isTest {
                    testSites[type, default: []].append(site)
                } else {
                    subjects[type]?.extensions.append(site)
                }
            }
        }
        return (subjects, testSites)
    }

    /// What the test targets' checks and the plugin's markers cover.
    private static func coverage(of files: [LawFileFacts], resolver: LawTypeResolver) -> Coverage {
        var coverage = Coverage()
        for file in files {
            for call in file.calls {
                record(call, in: file, resolver: resolver, into: &coverage)
            }
            for marker in file.markers {
                switch resolver.resolve(marker.typeName, in: file.module, file: file.file, scope: []) {
                case .resolved(let type):
                    coverage.suppressed[type, default: []].insert(marker.protocolName)

                case .ambiguous:
                    coverage.ambiguousNames.insert(marker.typeName)

                case .foreign, .unnamed:
                    break
                }
            }
        }
        return coverage
    }

    /// Adds what `call`, in `file`, covers to `coverage`: nothing when it
    /// checks a local type or a type outside the package, and an
    /// unresolved call when its subject is a generic parameter, an
    /// associated type or a typealias naming no plain type.
    private static func record(
        _ call: LawFileFacts.Call,
        in file: LawFileFacts,
        resolver: LawTypeResolver,
        into coverage: inout Coverage
    ) {
        guard let name = call.typeName else {
            coverage.unresolvedCalls += 1
            return
        }
        guard call.namesLocalType == false else {
            return
        }
        let head = name.split(separator: ".").first.map(String.init) ?? name
        guard resolver.binds(head, around: call.scope, in: file.module, file: file.file) == false else {
            coverage.unresolvedCalls += 1
            return
        }
        switch resolver.resolve(name, in: file.module, file: file.file, scope: call.scope) {
        case .resolved(let type):
            let covered = KitProtocols.covered(by: call.protocolName, ownOnly: call.ownOnly)
            coverage.called[type, default: []].formUnion(covered)

        case .ambiguous:
            coverage.ambiguousNames.insert(name)

        case .unnamed:
            coverage.unresolvedCalls += 1

        case .foreign:
            break
        }
    }

    /// The law check of `pair` on `subject`.
    private static func check(
        _ pair: LawSubject.Pair,
        of subject: LawSubject,
        coverage: Coverage,
        generatedFiles: Set<String>
    ) -> LawCheck {
        let called = coverage.called[subject.type] ?? []
        let bySuite = subject.primaries.filter(\.declaration.hasSuite).reduce(into: Set<String>()) { result, site in
            result.formUnion(KitProtocols.coveredBySuite(inheriting: site.declaration.writtenInherited))
        }
        let state: LawCheck.State
        let evidence: LawCheck.Evidence?
        if coverage.suppressed[subject.type]?.contains(pair.protocolName) == true {
            (state, evidence) = (.suppressed, .marker)
        } else if called.contains(pair.protocolName) {
            (state, evidence) = (.run, .call)
        } else if bySuite.contains(pair.protocolName) {
            (state, evidence) = (.run, .macro)
        } else if KitProtocols.waivedByFloatingPoint.contains(pair.protocolName),
                  called.union(bySuite).isDisjoint(with: KitProtocols.floatingPoint) == false {
            (state, evidence) = (.waived, nil)
        } else {
            (state, evidence) = (.unchecked, nil)
        }
        return LawCheck(
            type: subject.type.qualified,
            protocolName: pair.protocolName,
            provenance: pair.provenance,
            implementation: subject.implementation(of: pair),
            state: state,
            evidence: evidence,
            file: pair.site.file,
            line: pair.site.declaration.line,
            generated: generatedFiles.contains(pair.site.file)
        )
    }
}
