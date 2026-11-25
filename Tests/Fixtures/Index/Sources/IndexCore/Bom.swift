public func bomFirst() -> Int { 1 }

/// A file that starts with a byte order mark: the definition above is on
/// line 1, after its three bytes.
public func bomSecond() -> Int {
    bomFirst() + 1
}
