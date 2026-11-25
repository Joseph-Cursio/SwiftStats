//
//  IndexFixtureScanned.swift
//  SwiftStatsCoreTests
//
//  What `IndexFixtureScan` made on its scan's own thread (M7, design §13
//  steps 5a and 6a): the copy of the Index fixture, its fake toolchain and
//  what the scan gave (a snapshot scan's outcome, or the T1 group's runs
//  alone), handed to the awaiting test and removed once the test has
//  checked them.
//

@testable import SwiftStatsCore

/// The Index fixture's copy and its scan, made on another thread.
final class IndexFixtureScanned<Value>: @unchecked Sendable { // immutable; handed over once the thread has ended
    /// The copy.
    let fixture: BuildFixture
    /// The fake toolchain the scan built with.
    let toolchain: FakeToolchain
    /// What the scan gave.
    let value: Value

    /// The copy `fixture`, scanned with `toolchain` to give `value`.
    init(fixture: BuildFixture, toolchain: FakeToolchain, value: Value) {
        self.fixture = fixture
        self.toolchain = toolchain
        self.value = value
    }

    /// Removes the copy and the toolchain.
    func remove() {
        toolchain.remove()
        fixture.remove()
    }

    deinit {
        // Removal is `remove()`'s, called once the test has checked.
    }
}
