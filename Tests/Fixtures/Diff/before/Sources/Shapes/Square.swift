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
        let result = side * side
        return result
    }
}
