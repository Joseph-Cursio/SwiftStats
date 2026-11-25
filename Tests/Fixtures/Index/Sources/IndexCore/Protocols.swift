/// A protocol with a body-less requirement.
public protocol Shape {
    /// The shape's area.
    func area() -> Int
}

/// A shape whose witness is called only through the protocol.
struct Tile: Shape {
    /// The side length.
    let side: Int

    /// The witness of `Shape.area()`.
    func area() -> Int {
        side * side
    }
}

/// A protocol whose requirement has a default implementation.
protocol Greeter {
    /// A greeting.
    func greet() -> String
}

extension Greeter {
    /// The default implementation, reached only through its requirement.
    func greet() -> String {
        "hello"
    }
}

/// A greeter using the default implementation.
struct Host: Greeter {}

/// The total area of `shapes`, through the requirement.
public func totalArea(_ shapes: [any Shape]) -> Int {
    shapes.map { $0.area() }.reduce(0, +)
}

/// A unit tile.
public func unitTile() -> any Shape {
    Tile(side: 1)
}

/// A greeting, through the requirement.
public func welcome() -> String {
    let host: any Greeter = Host()
    return host.greet()
}
