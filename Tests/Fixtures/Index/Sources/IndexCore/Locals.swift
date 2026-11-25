/// Locals: a nested function and a local type with a member.
public func layout(_ width: Int) -> Int {
    func padded(_ value: Int) -> Int {
        value + 2
    }
    struct Square {
        let side: Int

        func area() -> Int {
            side * side
        }
    }
    return Square(side: padded(width)).area()
}

/// Two functions on one line.
func left() -> Int { 1 }; func right() -> Int { 2 }

/// A caller of the two functions on one line.
public func pair() -> Int {
    left() + right()
}

/// An unused local `let` and an unused local function in a used function.
public func summarize(_ values: [Int]) -> Int {
    let unusedTotal = values.count
    func unusedHelper() -> Int {
        0
    }
    return values.reduce(0, +)
}

/// Two local functions of one name in sibling scopes: the second's key is
/// numbered `#2`, and their USRs differ.
public func choose(_ flag: Bool) -> Int {
    if flag {
        func pick() -> Int {
            1
        }
        return pick()
    } else {
        func pick() -> Int {
            2
        }
        return pick()
    }
}
