//
//  SignalItem+Index.swift
//  SwiftStatsCore
//
//  The payloads M7's signals fill from the T1 build's index (design §8):
//  for test-only production code, a function's references from test
//  targets, counted as distinct test containers with the first five
//  named, and its module.
//

public extension SignalItem {
    /// Where a function's references come from, for a signal reading the
    /// index's referrers.
    struct References: Codable, Hashable, Sendable {
        /// Distinct test containers referencing it.
        public let tests: Int
        /// The first five of them, as the index block names them: record
        /// keys, or symbol names for containers that aren't records,
        /// sorted in code point order.
        public let testReferrers: [String]
        /// Its module, a target name.
        public let module: String
    }
}
