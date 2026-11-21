/// Runs its nested helper only when `flag` is set.
public func outer(_ flag: Bool) -> Int {
    func inner(_ value: Int) -> Int {
        value + 1
    }
    if flag {
        return inner(1)
    } else {
        return 0
    }
}

/// A nested function on its parent's line, never run.
public func sameLine() -> Int { func one() -> Int { 1 }; return 2 }

/// An empty list returns before the closure runs.
public func anyLarge(_ values: [Int]) -> Bool {
    values.isEmpty || values.contains { $0 > 100 }
}
