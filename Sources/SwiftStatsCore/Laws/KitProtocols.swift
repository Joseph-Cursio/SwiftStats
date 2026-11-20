//
//  KitProtocols.swift
//  SwiftStatsCore
//
//  The protocols SwiftPropertyLaws checks (PRD §7.11), copied from its
//  `KnownProtocol` (v4.11.0, package-scoped there, so it can't be linked):
//  the 33 names, which laws each check also runs, which protocols the
//  `@PropertyLawSuite` macro never emits, and which it drops as subsumed.
//  Compiled in, so the `swiftstats` build identity covers the table.
//

/// SwiftPropertyLaws' protocol table.
enum KitProtocols {
    /// The 33 protocols the kit has a `check<P>PropertyLaws` for, in the kit's order.
    static let known = [
        "Equatable", "Hashable", "Comparable", "Codable", "IteratorProtocol", "Sequence", "Collection",
        "BidirectionalCollection", "RandomAccessCollection", "MutableCollection", "RangeReplaceableCollection",
        "SetAlgebra", "Strideable", "RawRepresentable", "LosslessStringConvertible", "Identifiable",
        "CaseIterable", "AdditiveArithmetic", "Numeric", "SignedNumeric", "BinaryInteger", "SignedInteger",
        "UnsignedInteger", "FixedWidthInteger", "FloatingPoint", "BinaryFloatingPoint", "StringProtocol",
        "Semigroup", "Monoid", "CommutativeMonoid", "Group", "Semilattice", "Ring"
    ]
    /// `known` as a set.
    static let knownSet = Set(known)
    /// The kit's own algebraic protocols, which count only in a file that
    /// imports the kit and when the package declares no protocol so named.
    static let algebraic: Set<String> = ["Semigroup", "Monoid", "CommutativeMonoid", "Group", "Semilattice", "Ring"]
    /// Modules that export the kit's protocols.
    static let kitModules: Set<String> = ["PropertyLawKit", "PropertyLawMacro", "SwiftInferMacro"]
    /// Module qualifiers an inheritance entry may carry that name the same protocol.
    static let qualifiers = ["Swift.", "PropertyLawKit."]
    /// The `Package.resolved` and `Package.swift` identity of the kit.
    static let packageIdentity = "swiftpropertylaws"

    /// Protocols the macro never emits a check for.
    static let unemittable: Set<String> = ["IteratorProtocol", "Strideable", "CaseIterable"]
    /// Protocols whose laws a running `FloatingPoint` or
    /// `BinaryFloatingPoint` check waives, since IEEE-754 rounding breaks them.
    static let waivedByFloatingPoint: Set<String> = ["SignedNumeric", "Numeric", "AdditiveArithmetic"]
    /// The checks whose run waives `waivedByFloatingPoint`.
    static let floatingPoint: Set<String> = ["FloatingPoint", "BinaryFloatingPoint"]

    /// What each check also runs under the default `laws: .all`, transitively.
    static let runtimeInherited: [String: Set<String>] = [
        "Hashable": ["Equatable"],
        "Comparable": ["Equatable"],
        "Sequence": ["IteratorProtocol"],
        "Collection": ["Sequence", "IteratorProtocol"],
        "BidirectionalCollection": ["Collection", "Sequence", "IteratorProtocol"],
        "RandomAccessCollection": ["BidirectionalCollection", "Collection", "Sequence", "IteratorProtocol"],
        "MutableCollection": ["Collection", "Sequence", "IteratorProtocol"],
        "RangeReplaceableCollection": ["Collection", "Sequence", "IteratorProtocol"],
        "Strideable": ["Comparable", "Equatable"],
        "Numeric": ["AdditiveArithmetic"],
        "SignedNumeric": ["Numeric", "AdditiveArithmetic"],
        "BinaryInteger": ["Numeric", "AdditiveArithmetic"],
        "SignedInteger": ["BinaryInteger", "SignedNumeric", "Numeric", "AdditiveArithmetic"],
        "UnsignedInteger": ["BinaryInteger", "Numeric", "AdditiveArithmetic"],
        "FixedWidthInteger": ["BinaryInteger", "Numeric", "AdditiveArithmetic"],
        "BinaryFloatingPoint": ["FloatingPoint"],
        "StringProtocol": ["BidirectionalCollection", "Collection", "Sequence", "IteratorProtocol"],
        "Monoid": ["Semigroup"],
        "CommutativeMonoid": ["Monoid", "Semigroup"],
        "Group": ["Monoid", "Semigroup"],
        "Semilattice": ["CommutativeMonoid", "Monoid", "Semigroup"]
    ]

    /// What the macro treats each protocol as subsuming when it picks the
    /// most specific ones to emit: the runtime table, except that
    /// `Strideable` subsumes only `Comparable` and the floating-point
    /// protocols subsume the numeric ones they don't run.
    static let emitSubsumed: [String: Set<String>] = runtimeInherited.merging([
        "Strideable": ["Comparable"],
        "FloatingPoint": ["SignedNumeric", "Numeric", "AdditiveArithmetic"],
        "BinaryFloatingPoint": ["FloatingPoint", "SignedNumeric", "Numeric", "AdditiveArithmetic"]
    ]) { _, override in override }

    /// Raw types an enum can declare first, which make it `RawRepresentable`.
    static let rawValueTypes: Set<String> = [
        "String", "Character", "Substring", "Int", "Int8", "Int16", "Int32", "Int64", "Int128",
        "UInt", "UInt8", "UInt16", "UInt32", "UInt64", "UInt128",
        "Double", "Float", "Float16", "Float32", "Float64", "Float80", "CGFloat"
    ]

    /// The protocol a `check<P>PropertyLaws` function checks, when `name`
    /// is one and `P` is in the table.
    static func checkedProtocol(ofFunction name: String) -> String? {
        let prefix = "check"
        let suffix = "PropertyLaws"
        guard name.hasPrefix(prefix), name.hasSuffix(suffix), name.count > prefix.count + suffix.count else {
            return nil
        }
        let protocolName = String(name.dropFirst(prefix.count).dropLast(suffix.count))
        return knownSet.contains(protocolName) ? protocolName : nil
    }

    /// `protocolName` and what its check runs with it: everything it
    /// inherits unless `ownOnly`.
    static func covered(by protocolName: String, ownOnly: Bool) -> Set<String> {
        ownOnly ? [protocolName] : Set([protocolName]).union(runtimeInherited[protocolName] ?? [])
    }

    /// What `@PropertyLawSuite` checks for a primary declaration inheriting
    /// `names`, its clause's entries as written (the macro doesn't
    /// normalise them): the most specific emittable kit protocols among
    /// them, and what each of their checks runs.
    static func coveredBySuite(inheriting names: [String]) -> Set<String> {
        var protocols = Set(names).intersection(knownSet)
        if names.contains("Encodable"), names.contains("Decodable") {
            protocols.insert("Codable")
        }
        if protocols.contains("Strideable") {
            protocols.insert("Comparable")
        }
        protocols.subtract(unemittable)
        let subsumed = protocols.reduce(into: Set<String>()) { result, member in
            result.formUnion(emitSubsumed[member] ?? [])
        }
        return protocols.subtracting(subsumed).reduce(into: Set<String>()) { result, member in
            result.formUnion(covered(by: member, ownOnly: false))
        }
    }

    /// Whether `dependencies` include SwiftPropertyLaws.
    static func isDependency(in dependencies: DependencyReport) -> Bool {
        dependencies.direct.contains { $0.identity == packageIdentity }
            || dependencies.lockfile?.pins.contains { $0.identity == packageIdentity } == true
    }
}
