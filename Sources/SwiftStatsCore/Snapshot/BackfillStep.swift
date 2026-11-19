//
//  BackfillStep.swift
//  SwiftStatsCore
//
//  What happened to one picked commit of a backfill.
//

/// What happened to one picked commit.
public struct BackfillStep: Sendable {
    /// What was done.
    public enum Action: String, Sendable {
        /// Scanned and stored.
        case scanned
        /// Left alone: it already has a snapshot.
        case skipped
        /// Left alone: its snapshot holds results a backfill wouldn't collect.
        case kept
        /// The scan failed.
        case failed
    }

    /// The commit.
    public let commit: String
    /// What was done.
    public let action: Action
    /// Why, or what to know.
    public let note: String?
}
