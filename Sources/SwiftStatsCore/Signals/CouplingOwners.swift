//
//  CouplingOwners.swift
//  SwiftStatsCore
//
//  The owning type of a function family's root, for hidden coupling (M7,
//  design §4.3, §8.1): a package-declared type, read from the snapshot's
//  index results. A root the scan places in a type or an extension (it
//  has a type path) and holding a Swift USR is owned by the production
//  type whose USR is the longest proper prefix of its own: a member's USR
//  begins with its context's mangling, and an extension member's context
//  is the extended type's mangling (followed by the extension's module
//  and `E`), so ownership follows the USR, as §4.3's `extendedBy` rule
//  does, whatever the extension's head is spelled as (a qualified name, a
//  typealias) and whichever target declares the type. An extension of a
//  type the package doesn't declare (`Array`, or another module's type of
//  a name a package target declares too) has no owner. A root without a
//  Swift USR (none, or a `c:` one) is owned only by the production type
//  its own target, type path and type file name. Free functions, and the
//  local functions and local types' members the scan gives no type path,
//  have no owning type. A root's USR is its record's by key, the first
//  record's holding one for a key several records hold.
//

/// The owning types of families' roots.
struct CouplingOwners {
    /// The prefix of a Swift USR.
    private static let swiftPrefix = "s:"

    /// The production types, by identity.
    private let types: Set<TypeIdentity>
    /// The production types by USR; the first by identity when several
    /// share one.
    private let typesByUSR: [String: TypeIdentity]
    /// The lengths of the production types' USRs, longest first.
    private let lengths: [Int]
    /// The records' primary USRs by key, the first record's holding one
    /// for a key several records hold.
    private let usrs: [String: String]

    /// The owners `index`'s production types give.
    init(index: IndexReport) {
        let identified = index.types.map { type in
            (type.usr, TypeIdentity(module: type.module, typePath: type.typePath, typeFile: type.typeFile ?? ""))
        }
        types = Set(identified.map(\.1))
        typesByUSR = Dictionary(identified) { first, _ in first }
        lengths = Set(typesByUSR.keys.map(\.count)).sorted(by: >)
        usrs = Dictionary(index.records.compactMap { record in record.usr.map { (record.key, $0) } }) { first, _ in
            first
        }
    }

    /// Whether one of `first` and `second` is nested in the other (design
    /// §8.1's Y), as the type cycles read nesting (`TypeIdentity.isNested(in:)`):
    /// in the same target, one type path the other's followed by `.`, the
    /// outer type not file-scoped or file-scoped in the inner one's file, so
    /// a `private` type nested in a plain one is nested in it.
    static func isNested(_ first: TypeIdentity, _ second: TypeIdentity) -> Bool {
        first.isNested(in: second) || second.isNested(in: first)
    }

    /// The owning type of `family`'s root (a computed property's first
    /// accessor); nil when it has none.
    func owner(of family: FunctionFamily) -> TypeIdentity? {
        let row = family.root ?? family.members[0]
        guard let path = row.typePath, path.isEmpty == false else {
            return nil
        }
        guard let usr = usrs[row.key], usr.hasPrefix(Self.swiftPrefix) else {
            let own = TypeIdentity(module: row.module, typePath: path, typeFile: row.typeFile ?? "")
            return types.contains(own) ? own : nil
        }
        return owner(ofUSR: usr)
    }

    /// The production type whose USR is the longest proper prefix of
    /// `usr`; nil when none is.
    private func owner(ofUSR usr: String) -> TypeIdentity? {
        let count = usr.count
        for length in lengths where length < count {
            if let type = typesByUSR[String(usr.prefix(length))] {
                return type
            }
        }
        return nil
    }
}
