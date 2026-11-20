/// Sums the prices of the items whose quantity is positive.
public func total(of items: [Item]) -> Int {
    var sum = 0
    for item in items where item.quantity > 0 {
        sum += item.price * item.quantity
    }
    return sum
}

/// An item on an order.
public struct Item {
    /// The unit price.
    public var price: Int
    /// How many were ordered.
    public var quantity: Int
}
