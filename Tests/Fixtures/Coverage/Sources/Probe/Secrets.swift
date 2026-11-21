/// Another file's type of the same name; no test runs it.
fileprivate struct Secret {
    /// Its seed.
    var seed = 2
}

/// The seed of this file's secret.
public func secondSecret() -> Int {
    Secret().seed
}
