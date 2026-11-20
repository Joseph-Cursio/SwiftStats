//
//  PropertyTestLinks.swift
//  SwiftStatsCore
//
//  Finds the property tests that check a suggestion (PRD §7.11), first
//  match wins. Generated: a test-target file whose leading comments hold
//  `// Suggestion identity: 0x<16 uppercase hex>`, as the files
//  SwiftInferProperties writes do, links its tests to that identity
//  exactly. Macro: `@CheckProperty` expands into a test of one law, so it
//  links a suggestion of that law's template: `.idempotent` or
//  `.preservesInvariant` on the suggestion's function, and for a round trip
//  `.roundTrip` on the function paired with its partner, or on the
//  resolved partner paired with the function. Handwritten, a heuristic: a
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
    /// The ASCII characters an operator is made of.
    private static let operatorCharacters = Set("/=-+!*%<>&|^~?.")

    /// The tests in each identity's generated files, sorted.
    private let stubTests: [String: [String]]
    /// The laws the `@CheckProperty` tests on each function record check,
    /// by record key.
    private let macroChecks: [String: Set<CheckPropertyKind>]
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
        let message = MarkerCollector.propertyTestMessage(CheckPropertyKind.attribute)
        var checks: [String: Set<CheckPropertyKind>] = [:]
        for finding in findings where finding.tool == MarkerCollector.tool
            && finding.rule == MarkerCollector.propertyTestRule && finding.message == message {
            guard let location = finding.locations.first, location.attachedTo == .function,
                  let owner = location.owner,
                  let kind = measured.checkProperties[
                      RawFinding.Place(file: location.file, line: location.line, column: location.column)
                  ] else {
                continue
            }
            checks[owner, default: []].insert(kind)
        }
        macroChecks = checks
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

    /// Whether a `@CheckProperty` test checks `candidate`'s law, `primary`
    /// being its function: `.idempotent` there for an idempotence template,
    /// `.preservesInvariant` there for invariant preservation, and for a
    /// round trip `.roundTrip` there paired with the partner's base name, or
    /// on the resolved partner paired with `primary`'s name.
    private func isCheckedByMacro(_ candidate: PropertyCandidate, primary: FunctionRecord) -> Bool {
        let own = macroChecks[primary.key] ?? []
        switch candidate.template {
        case CheckPropertyKind.roundTripTemplate:
            let onPrimary = candidate.partner.map { own.contains(.roundTrip(pairedWith: Self.baseName($0))) } ?? false
            let onPartner = candidate.partnerKey.flatMap { macroChecks[$0] }?
                .contains(.roundTrip(pairedWith: primary.name)) ?? false
            return onPrimary || onPartner

        case CheckPropertyKind.invariantTemplate:
            return own.contains(.preservesInvariant)

        default:
            return CheckPropertyKind.idempotenceTemplates.contains(candidate.template) && own.contains(.idempotent)
        }
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
        if isCheckedByMacro(candidate, primary: primary) {
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
