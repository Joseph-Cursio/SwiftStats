import Foundation

/// A protocol: requirements without bodies get no record.
public protocol Shape {
    var area: Double { get }
    func scaled(by factor: Double) -> Self
    subscript(index: Int) -> Double { get }
}

public struct Square: Shape {
    public var side: Double

    public init(side: Double) {
        self.side = side
    }

    public init?(text: String) {
        guard let side = Double(text) else { return nil }
        self.side = side
    }

    // Computed property: one implicit-getter record.
    public var area: Double {
        side * side
    }

    // Explicit accessors: one record each.
    public var perimeter: Double {
        get { side * 4 }
        set { side = newValue / 4 }
    }

    // Observers on a stored property.
    public var label = "" {
        willSet { print("will set \(newValue)") }
        didSet { print("did set \(oldValue)") }
    }

    public func scaled(by factor: Double) -> Square {
        // A nested function gets its own record.
        func clamp(_ value: Double) -> Double {
            max(0, value)
        }
        return Square(side: clamp(side * factor))
    }

    public subscript(index: Int) -> Double {
        side * Double(index)
    }

    public subscript(row row: Int, column column: Int) -> Double {
        get { Double(row * column) }
        set { side = newValue }
    }

    public static func + (lhs: Square, rhs: Square) -> Square {
        Square(side: lhs.side + rhs.side)
    }

    public static prefix func - (shape: Square) -> Square {
        Square(side: -shape.side)
    }
}

public extension Shape where Self: Equatable {
    func isSame(as other: Self) -> Bool {
        self == other
    }
}
