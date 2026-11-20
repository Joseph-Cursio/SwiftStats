// No kit import here, so Monoid is not the kit's protocol: no pair.
public struct Tally: Monoid, Equatable {
    public let count: Int
}
