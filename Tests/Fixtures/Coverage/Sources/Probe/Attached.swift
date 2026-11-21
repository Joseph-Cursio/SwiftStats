/// A value worked out once by a closure, outside every function.
public let globalValue: Int = { 40 + 2 }()

/// Applies `transform`, whose default is a closure in the signature.
public func withDefault(_ transform: (Int) -> Int = { $0 + 1 }) -> Int {
    transform(1)
}

/// A type only this file sees.
fileprivate struct Secret {
    /// Its seed, an initial value of its own.
    var seed = 1
}

/// The seed of this file's secret.
public func firstSecret() -> Int {
    Secret().seed
}
