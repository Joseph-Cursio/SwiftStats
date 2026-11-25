/// A `var` never mutated and a call to a deprecated function.
public func warned() -> Int {
    var constant = 3
    return constant + legacy()
}

/// A deprecated function its own module calls.
@available(*, deprecated, message: "use warned()")
func legacy() -> Int {
    1
}

/// Code after `return`.
public func unreachable() -> Int {
    return 1
    print("never")
}

#warning("remember to finish this")
