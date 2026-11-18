//
//  FindingTarget.swift
//  SwiftStatsCore
//
//  What a finding's location attaches to (PRD §7.16).
//

/// What a finding's location attaches to.
public enum FindingTarget: String, Codable, CaseIterable, Sendable {
    /// A scanned file, outside any function or type.
    case file
    /// The innermost function record whose lines hold it.
    case function
    /// The innermost type whose lines hold it, outside any function.
    case type
    /// A file SwiftStats didn't scan.
    case unscanned
}
