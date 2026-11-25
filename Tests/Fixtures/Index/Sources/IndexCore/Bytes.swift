import Foundation

/// The size of `value`: `Data` is `Foundation.Data` in this file, which
/// imports only `Foundation`. Its key is the one `measure(_:)` in
/// Dependency.swift has: a key collision the USR separates.
func measure(_ value: Data) -> Int {
    value.count
}

/// The size of a two-byte buffer.
public func bufferSize() -> Int {
    measure(Data([1, 2]))
}
