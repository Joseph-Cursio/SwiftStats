//
//  HelperCaller.swift
//  SwiftStatsCore
//
//  Where a call to a test helper is written (M5, `TestHelperExpansion`):
//  the caller's test target and file, and the types whose members it can
//  call bare or on `self` / `Self`. Those are the types around it, its own
//  and those enclosing it (Swift's unqualified lookup finds an enclosing
//  type's static members), and the types each of those inherits from in
//  the target, followed through the target's types by simple name (an
//  `XCTestCase` subclass reaches its base class's helpers).
//

/// Where a call to a test helper is written.
struct HelperCaller {
    /// The caller's test target.
    let module: String
    /// The caller's file.
    let file: String
    /// The simple names, without backticks, of the types whose members it
    /// calls bare or on `self` / `Self`.
    let types: Set<String>

    /// The caller declared by `record`, in the test target `target`.
    init(_ record: FunctionRecord, target: HelperTarget) {
        module = record.module
        file = record.file
        var reached = Set<String>()
        var pending = record.typePath.map(TypePathMatch.components(of:)) ?? []
        while let name = pending.popLast() {
            guard reached.insert(name).inserted else {
                continue
            }
            pending += target.inherited[name] ?? []
        }
        types = reached
    }
}
