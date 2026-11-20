import PropertyLawKit

// Hashable is synthesised; Comparable writes `<`; Semigroup, a kit
// protocol named in a file that imports the kit, is always custom.
public struct Money: Hashable, Comparable {
    public let cents: Int

    public static func < (lhs: Money, rhs: Money) -> Bool {
        lhs.cents < rhs.cents
    }
}

extension Money: Semigroup {
    public static func combine(_ lhs: Money, _ rhs: Money) -> Money {
        Money(cents: lhs.cents + rhs.cents)
    }
}
