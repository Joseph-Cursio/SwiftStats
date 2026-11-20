import PropertyLawMacro

// A FloatingPoint check runs, which waives Numeric and AdditiveArithmetic.
public struct Fixed: FloatingPoint, Numeric, AdditiveArithmetic {
    let bits: Int
}

// The suite runs Comparable; CaseIterable is never emitted, the raw type's
// RawRepresentable is not in the clause, and Codable comes by extension.
@PropertyLawSuite
public enum Tone: String, Comparable, CaseIterable {
    case low
    case high
}

extension Tone: Codable {}

// Checked with laws: .ownOnly, so Equatable isn't run with Hashable.
public struct Grade: Hashable, Equatable {
    let value: Int
}

// Checked without it, so Equatable runs with Hashable.
public struct Rank: Hashable, Equatable {
    let value: Int
}

// The suite macro matches `Swift.Hashable` as written and emits nothing.
@PropertyLawSuite
public struct Width: Swift.Hashable {
    let value: Int
}
