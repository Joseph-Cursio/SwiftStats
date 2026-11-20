@testable import Core
import Testing

/// Sums the prices of the items whose quantity is positive.
func expectedTotal(of items: [Item]) -> Int {
    var sum = 0
    for item in items where item.quantity > 0 {
        sum += item.price * item.quantity
    }
    return sum
}

@Test func totals() {
    #expect(total(of: []) == expectedTotal(of: []))
}
