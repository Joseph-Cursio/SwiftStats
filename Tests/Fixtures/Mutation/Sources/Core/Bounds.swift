/// `value` held between `low` and `high`. The tests run every line but
/// check only that the result isn't negative, so its mutants survive:
/// weak tests.
public func clamp(_ value: Int, low: Int, high: Int) -> Int {
    if value < low {
        return low
    }
    if value > high {
        return high
    }
    return value
}

/// Whether `value` lies between `low` and `high`, both included. Tested
/// exactly, so its mutants are killed; the `--since` patch's line in
/// `clamp` moves it down.
public func isWithin(_ value: Int, low: Int, high: Int) -> Bool {
    value >= low && value <= high
}
