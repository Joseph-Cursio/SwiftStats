//
//  TrendPoint.swift
//  SwiftStatsCore
//
//  One point of a trend: a commit, its date, the metric's value there and why
//  it may not compare with the point before.
//

/// One point of a trend.
public struct TrendPoint: Codable, Hashable, Sendable {
    /// The commit.
    public let commit: String
    /// Its committer date.
    public let date: String
    /// The number; nil when that snapshot doesn't have it, or when it is a
    /// mutation count and that snapshot's results leave files out.
    public let value: Double?
    /// Why this point doesn't compare with the one before; nil when it does.
    public let breakReason: String?
}
