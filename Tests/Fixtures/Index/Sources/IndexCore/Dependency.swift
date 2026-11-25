import IndexDepKit

/// A value from the local path dependency.
public func withDependency() -> Int {
    depValue() + 1
}

/// The size of `value`: `Data` is `IndexDepKit.Data` in this file, which
/// imports only `IndexDepKit`. Its key is the one `measure(_:)` in Bytes.swift
/// has, where `Data` is `Foundation.Data`: a key collision the USR separates.
func measure(_ value: Data) -> Int {
    value.size
}

/// The size of a dependency payload.
public func payloadSize() -> Int {
    measure(Data(size: 2))
}
