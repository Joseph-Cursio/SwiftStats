//
//  IndexFixtureScanned.swift
//  SwiftStatsCoreTests
//
//  What `IndexFixtureScan` made on its scan's own thread (M7, design §13
//  step 5a): the copy of the Index fixture and the scan's outcome, with
//  its fake toolchain, handed to the awaiting test and removed once the
//  test has checked them.
//

@testable import SwiftStatsCore

/// The Index fixture's copy and its scan, made on another thread.
final class IndexFixtureScanned: @unchecked Sendable { // immutable; handed over once the thread has ended
    /// The copy.
    let fixture: BuildFixture
    /// What the scan gave, with its toolchain.
    let outcome: IndexGroupHarness.Outcome

    /// The copy `fixture` and its scan's `outcome`.
    init(fixture: BuildFixture, outcome: IndexGroupHarness.Outcome) {
        self.fixture = fixture
        self.outcome = outcome
    }

    /// Removes the copy and the toolchain.
    func remove() {
        outcome.toolchain.remove()
        fixture.remove()
    }

    deinit {
        // Removal is `remove()`'s, called once the test has checked.
    }
}
