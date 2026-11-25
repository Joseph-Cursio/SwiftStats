//
//  IndexFixtureScanError.swift
//  SwiftStatsCoreTests
//
//  A recording `IndexFixtureScan` can't use (M7, design §13 step 5a).
//

/// A recording the Index fixture's scan harness can't use.
struct IndexFixtureScanError: Error, CustomStringConvertible {
    /// What is wrong with it.
    let description: String
}
