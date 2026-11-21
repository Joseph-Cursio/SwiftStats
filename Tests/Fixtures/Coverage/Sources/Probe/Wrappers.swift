/// Keeps a value at most 10.
@propertyWrapper
public struct Clamped {
    /// The clamped value.
    private var value: Int
    /// The value, clamped when set.
    public var wrappedValue: Int {
        get { value }
        set { value = min(newValue, 10) }
    }

    /// Clamps the initial value.
    public init(wrappedValue: Int) {
        value = min(wrappedValue, 10)
    }
}

/// Settings with a clamped level.
public struct Settings {
    /// The level, at most 10.
    @Clamped public var level = 3

    /// Default settings.
    public init() {}
}

/// A value on one side.
public enum Side {
    /// The left side.
    case left(Int)
}

/// Each value put on the left: the case as a function value gives two
/// entries with one region.
public func lefts(_ values: [Int]) -> [Side] {
    values.map(Side.left)
}
