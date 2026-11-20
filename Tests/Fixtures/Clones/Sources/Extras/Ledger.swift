import Core

/// Sums the prices of the items whose quantity is positive.
public func total(of items: [Item]) -> Int {
    var sum = 0
    for item in items where item.quantity > 0 {
        sum += item.price * item.quantity
    }
    return sum
}
