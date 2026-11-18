//
//  FindingKind.swift
//  SwiftStatsCore
//
//  Census or defect (PRD §6.4).
//

/// Whether a finding counts something or claims a problem at a place.
public enum FindingKind: String, Codable, CaseIterable, Sendable {
    /// Counts something that needs no action per item.
    case census
    /// A claim about a specific place, worth reading each time.
    case defect
}
