// DO NOT EDIT: written by a generator.

/// Sums the prices of the items whose quantity is positive.
public func generatedTotal(of items: [Item]) -> Int {
    var sum = 0
    for item in items where item.quantity > 0 {
        sum += item.price * item.quantity
    }
    return sum
}
