//
//  DeadCodeRun.swift
//  SwiftStatsCore
//
//  outskirts' two runs over the T1 build's store (M7, design §5.2): the
//  `roots` run, test targets as roots, for the unused-declaration counts
//  and the line ratio's dead lines; the `production` run, tests left out
//  of the roots, for production-dead code.
//

/// One of outskirts' two runs.
public enum DeadCodeRun: String, Codable, CaseIterable, Sendable {
    /// Tests excluded from the roots: production-dead code.
    case production
    /// Test targets as roots: anything a test reaches is used.
    case roots

    /// The runs in the order SwiftStats makes and lists them.
    public static let ordered: [Self] = [.roots, .production]
}
