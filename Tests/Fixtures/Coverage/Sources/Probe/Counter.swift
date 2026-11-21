/// A running total.
public struct Counter {
    /// The total so far; its initial value is a function of its own.
    public var total = 0

    /// An empty counter.
    public init() {}

    /// Adds twice each of `values`, through a closure.
    public mutating func add(_ values: [Int]) {
        total += values.map { $0 * 2 }.reduce(0, +)
    }

    /// The total, doubled by a private function.
    public func doubled() -> Int {
        twice(total)
    }
}

/// `value` doubled; private, so its profile name carries its file.
private func twice(_ value: Int) -> Int {
    value * 2
}

/// Run only by the second test target.
public func onlyKit() -> Int {
    7
}

/// Run by no test.
public func neverCalled() -> Int {
    9
}
