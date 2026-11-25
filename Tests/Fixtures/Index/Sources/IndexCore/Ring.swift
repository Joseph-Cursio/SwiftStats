/// A collection of three positions. Its get-only `subscript(position:)`
/// witnesses `Collection`'s borrowed requirement, so the compiler adds a
/// `_read` accessor, timed at the `subscript` keyword, beside the getter
/// timed at its `{`.
public struct Ring: Collection {
    /// An empty ring.
    public init() {}

    /// The first position.
    public var startIndex: Int {
        0
    }

    /// The position past the last.
    public var endIndex: Int {
        3
    }

    /// The position after `position`.
    public func index(after position: Int) -> Int {
        position + 1
    }

    /// The value at `position`.
    public subscript(position: Int) -> Int {
        position * 10
    }
}

/// A global whose initialiser is type-checked as an expression of this
/// file, outside every function: its timing attaches to the file.
let defaultWidths = [1, 2, 3].map { $0 * 2 }

/// The sum of the default widths and the ring's values.
public func totalWidth() -> Int {
    defaultWidths.reduce(0, +) + Ring().reduce(0, +)
}
