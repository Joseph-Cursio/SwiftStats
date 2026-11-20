//
//  PropertyTestLinks.swift
//  SwiftStatsCore
//
//  Finds the property tests that check a suggestion (PRD §7.11), first
//  match wins. Generated: a test-target file whose leading comments hold
//  `// Suggestion identity: 0x<16 uppercase hex>`, as the files
//  SwiftInferProperties writes do, links its tests to that identity
//  exactly. Macro: `@CheckProperty` on the suggestion's function or its
//  partner expands into a property test. Handwritten, a heuristic: a
//  property test outside generated files, in a test target depending on the
//  function's module directly or through other targets, calls the function
//  or its partner by base name, or uses it as an operator.
//

import SwiftSyntax

/// Links suggestions to the property tests that check them.
struct PropertyTestLinks {
    /// A property test the heuristic reads.
    private struct PropertyTest {
        /// The test's key.
        let key: String
        /// The test's module.
        let module: String
        /// The base names it calls.
        let callees: Set<String>
    }

    /// The comment before a generated file's identity.
    private static let identityPrefix = "// Suggestion identity: "
    /// An identity's prefix.
    private static let hexPrefix = "0x"
    /// The hex digits of an identity.
    private static let hexDigits = 16
    /// The uppercase hex digits.
    private static let upperHex = Set("0123456789ABCDEF")
    /// The attribute that expands into a property test on its function.
    private static let checkProperty = "CheckProperty"
    /// The ASCII characters an operator is made of.
    private static let operatorCharacters = Set("/=-+!*%<>&|^~?.")

    /// The tests in each identity's generated files, sorted.
    private let stubTests: [String: [String]]
    /// The function records `@CheckProperty` is on.
    private let macroOwners: Set<String>
    /// Function records by key.
    private let records: [String: FunctionRecord]
    /// Property tests outside generated files.
    private let propertyTests: [PropertyTest]
    /// Each target's own targets, direct dependencies and theirs.
    private let reach: [String: Set<String>]

    /// The links of `measured`'s tests, `findings`' markers and `targets`'
    /// dependencies.
    init(measured: ScanMeasurements, findings: [Finding], targets: [TargetSummary]) {
        let testsByFile = Dictionary(grouping: measured.tests, by: \.file)
        stubTests = measured.stubs.mapValues { files in
            files.flatMap { testsByFile[$0] ?? [] }.map(\.key).sorted()
        }
        let message = MarkerCollector.propertyTestMessage(Self.checkProperty)
        macroOwners = Set(findings.compactMap { finding in
            guard finding.tool == MarkerCollector.tool, finding.rule == MarkerCollector.propertyTestRule,
                  finding.message == message, let location = finding.locations.first,
                  location.attachedTo == .function else {
                return nil
            }
            return location.owner
        })
        records = Dictionary(measured.records.map { ($0.key, $0) }) { first, _ in first }
        propertyTests = measured.tests
            .filter { $0.kind == .property && $0.generated == false }
            .map { PropertyTest(key: $0.key, module: $0.module, callees: measured.propertyCallees[$0.key] ?? []) }
        reach = Self.reach(targets)
    }

    /// The identities the leading comments of `tree` carry.
    static func stubIdentities(in tree: SourceFileSyntax) -> [String] {
        let trivia = tree.firstToken(viewMode: .sourceAccurate)?.leadingTrivia ?? []
        return trivia.compactMap { piece in
            guard case .lineComment(let text) = piece, text.hasPrefix(identityPrefix) else {
                return nil
            }
            var identity = text.dropFirst(identityPrefix.count)
            while identity.last?.isWhitespace == true {
                identity = identity.dropLast()
            }
            let digits = identity.dropFirst(hexPrefix.count)
            guard identity.hasPrefix(hexPrefix), digits.count == hexDigits, digits.allSatisfy(upperHex.contains) else {
                return nil
            }
            return String(identity)
        }
    }

    /// Each target's dependencies within the package, followed through.
    private static func reach(_ targets: [TargetSummary]) -> [String: Set<String>] {
        let direct = Dictionary(targets.map { ($0.name, $0.dependencies) }) { first, _ in first }
        return direct.mapValues { dependencies in
            var reached = Set<String>()
            var pending = dependencies
            while let next = pending.popLast() {
                if reached.insert(next).inserted {
                    pending += direct[next] ?? []
                }
            }
            return reached
        }
    }

    /// The base name of a function as SwiftInferProperties names it:
    /// `decoded` for `decoded(_:)` or `Money.decoded(_:)`, and for an
    /// operator the whole operator: `..<` for `..<(_:_:)` or
    /// `Money...<(_:_:)`. An operator starts at its first operator
    /// character that begins the name or follows a dot, since only an
    /// operator starting with a dot may contain one.
    static func baseName(_ function: String) -> String {
        let name = function.split(separator: "(", maxSplits: 1, omittingEmptySubsequences: false).first ?? ""
        let characters = Array(name)
        let start = characters.indices.first { index in
            operatorCharacters.contains(characters[index]) && (index == 0 || characters[index - 1] == ".")
        }
        if let start {
            return String(characters[start...])
        }
        return name.split(separator: ".").last.map(String.init) ?? String(name)
    }

    /// `candidate` with the first link that finds a property test checking it.
    func linked(_ candidate: PropertyCandidate) -> PropertyCandidate {
        var linked = candidate
        if let tests = stubTests[candidate.identity] {
            linked.testedBy = .generated
            linked.testKeys = tests
            return linked
        }
        guard let location = candidate.location, location.attachedTo == .function,
              let owner = location.owner, let primary = records[owner] else {
            return linked
        }
        if ([owner] + [candidate.partnerKey].compactMap(\.self)).contains(where: macroOwners.contains) {
            linked.testedBy = .macro
            return linked
        }
        let names = Set([primary.name] + [candidate.partner.map(Self.baseName)].compactMap(\.self))
        let tests = propertyTests
            .filter { test in
                reach[test.module]?.contains(primary.module) == true && test.callees.isDisjoint(with: names) == false
            }
            .map(\.key)
            .sorted()
        if tests.isEmpty == false {
            linked.testedBy = .handwritten
            linked.testKeys = tests
        }
        return linked
    }
}
