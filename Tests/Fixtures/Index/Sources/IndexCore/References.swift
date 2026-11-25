/// A base class another package class inherits.
public class Vehicle {
    /// A vehicle.
    public init() {}

    /// The number of wheels.
    public func wheels() -> Int {
        4
    }
}

/// A subclass: its inheritance clause references `Vehicle`.
public final class Bike: Vehicle {
    /// The override of `wheels()`.
    override public func wheels() -> Int {
        2
    }
}

extension Bike: CustomStringConvertible {
    /// A conformance an extension adds.
    public var description: String {
        "bike"
    }
}

/// A property production code reads and only a test writes.
struct Threshold {
    /// The stored level.
    var stored = 3

    /// The level: read in production, written only by a test.
    var level: Int {
        get {
            stored
        }
        set {
            stored = newValue
        }
    }
}

/// The current level, read through the getter.
public func currentLevel() -> Int {
    Threshold().level
}
