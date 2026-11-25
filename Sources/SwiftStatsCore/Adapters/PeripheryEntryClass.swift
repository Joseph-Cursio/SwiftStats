//
//  PeripheryEntryClass.swift
//  SwiftStatsCore
//
//  What an outskirts entry is to SwiftStats (M7, design §5.3), the first
//  that applies, in the order `PeripheryOutput.rule` gives and
//  `PeripheryOutput.entryClass(of:)` applies: under the
//  build directory, outside the package root, in a test target, in a file
//  the scan didn't parse, in a file that changed during the scan (its
//  position may be stale), a local variable (outskirts reports one as a
//  global once locals are indexed), else production code. Only production
//  entries are mapped to records; the others are counted apart.
//

/// The class of an outskirts entry.
public enum PeripheryEntryClass: String, Sendable {
    /// Under the build directory (none expected, given the exclude).
    case build
    /// In a file that changed during the scan.
    case fileChanged
    /// A local variable.
    case local
    /// Outside the package root.
    case outsideRoot
    /// Production code: mapped to records.
    case production
    /// In a test target.
    case test
    /// In the root, in a file the scan didn't parse.
    case unscanned
}
