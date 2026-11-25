/// One half of a cycle: it reaches `Beta` only from a method in its
/// extension.
struct Alpha {
    /// A value.
    let value: Int
}

/// The other half of the cycle.
struct Beta {
    /// An `Alpha`.
    func make() -> Alpha {
        Alpha(value: 1)
    }
}

extension Alpha {
    /// The edge from `Alpha` to `Beta`, through an extension member.
    func partner() -> Beta {
        Beta()
    }
}

/// A type with a nested `Index` that references it back.
struct Ledger {
    /// The entries.
    var entries: [Int]

    /// A position in a ledger.
    struct Index {
        /// The position.
        let position: Int

        /// The entry at the position in `ledger`.
        func entry(in ledger: Ledger) -> Int {
            ledger.entries[position]
        }
    }

    /// The index of `position`.
    func index(at position: Int) -> Index {
        Index(position: position)
    }
}

extension Array where Element == Int {
    /// Every element doubled: an extension method of a type the package
    /// doesn't declare.
    func doubledAll() -> [Int] {
        map { $0 * 2 }
    }
}

extension Array {
    /// The second element, if any: another, unrelated one.
    func secondItem() -> Element? {
        count > 1 ? self[1] : nil
    }
}

/// Uses the cycle.
public func cycle() -> Int {
    Beta().make().partner().make().value
}

/// Uses the ledger and its index.
public func ledgerEntry() -> Int {
    let ledger = Ledger(entries: [4])
    return ledger.index(at: 0).entry(in: ledger)
}

/// Uses both `Array` extension methods.
public func arrayUse() -> Int {
    [1, 2].doubledAll().secondItem() ?? 0
}
