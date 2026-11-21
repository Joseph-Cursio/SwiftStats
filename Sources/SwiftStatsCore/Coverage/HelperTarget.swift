//
//  HelperTarget.swift
//  SwiftStatsCore
//
//  A test target's types, as calls to its test helpers name them (M5,
//  `TestHelperExpansion`): what each type inherits, which types it
//  declares and which it only extends, and the types its typealiases
//  name. Types are by simple name; local types are left out.
//

/// A test target's types, as helper calls name them.
struct HelperTarget {
    /// A target with no types.
    static let empty = Self(inherited: [:], declared: [], named: [], aliases: [:])

    /// The simple names of what each type inherits, by simple name; all
    /// names here are without backticks.
    let inherited: [String: [String]]
    /// The simple names of the types it declares.
    let declared: Set<String>
    /// The simple names of the types it declares or extends.
    let named: Set<String>
    /// The simple names of the types each typealias names, by alias.
    let aliases: [String: Set<String>]

    /// The test targets of `measured`, by name; a target with no types is
    /// left out.
    static func targets(in measured: ScanMeasurements) -> [String: Self] {
        let byModule = Dictionary(grouping: measured.types.filter { $0.isLocal == false }, by: \.module)
        var targets: [String: Self] = [:]
        for module in Set(byModule.keys).union(measured.testAliases.keys) {
            let types = byModule[module] ?? []
            var parents: [String: [String]] = [:]
            for type in types {
                parents[simpleName(type.name), default: []] += type.conformances.map(simpleName)
            }
            targets[module] = Self(
                inherited: parents,
                declared: Set(types.filter { $0.kind != .extensionDeclaration }.map { simpleName($0.name) }),
                named: Set(types.map { simpleName($0.name) }),
                aliases: measured.testAliases[module] ?? [:]
            )
        }
        return targets
    }

    /// The simple name of the type at `path`, without backticks.
    private static func simpleName(_ path: String) -> String {
        TestReferences.unescaped(CoverageWitnesses.simpleName(of: path))
    }

    /// Whether the chain of names `written` that a call is written on may
    /// be the type whose simple name is `typeName`, qualified by a suffix of
    /// `allowed` (`TypePathMatch`). A typealias names the types it names.
    /// A chain ending in a type of the target must name that type. Any
    /// other chain ending in a capitalised name is a type outside the
    /// target, which no helper is a member of. Otherwise it is a value,
    /// whose type isn't read.
    func admits(_ written: [String], typeName: String, allowed: [String]) -> Bool {
        guard let last = written.last else {
            return false
        }
        if let aliased = aliases[last] {
            return aliased.contains(typeName)
        }
        if named.contains(last) {
            return last == typeName && TypePathMatch.isSuffix(Array(written.dropLast()), of: allowed)
        }
        return last.first?.isUppercase != true
    }
}
