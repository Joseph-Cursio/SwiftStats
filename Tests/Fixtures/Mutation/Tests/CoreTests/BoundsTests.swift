import Core
import Testing

/// Runs every line of `clamp` but checks only that its result isn't
/// negative, so its mutants survive.
@Test func clampStaysNonNegative() {
    #expect(clamp(3, low: 5, high: 10) >= 0)
    #expect(clamp(20, low: 5, high: 10) >= 0)
    #expect(clamp(7, low: 5, high: 10) >= 0)
}

/// Checks `isWithin` exactly, at both bounds and past them.
@Test func isWithinChecksBothBounds() {
    #expect(isWithin(5, low: 0, high: 10))
    #expect(isWithin(0, low: 0, high: 10))
    #expect(isWithin(10, low: 0, high: 10))
    #expect(isWithin(-1, low: 0, high: 10) == false)
    #expect(isWithin(11, low: 0, high: 10) == false)
}
