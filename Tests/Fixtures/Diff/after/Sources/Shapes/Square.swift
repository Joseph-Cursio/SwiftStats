/// A square.
public struct Square {
    /// The side length.
    public let side: Int

    /// A square with sides of `side`.
    public init(side: Int) {
        self.side = side
    }

    /// The area: changed in `after`.
    public func area() -> Int {
        guard side > 0 else {
            return 0
        }
        return side * side
    }
}
