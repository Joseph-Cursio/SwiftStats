//
//  IndexDefinitions.swift
//  SwiftStatsCore
//
//  Counts of the function-like definitions the USR join met (M7, design
//  §3): the distinct definitions it assigned to records (primary USRs,
//  counted before disagreements take theirs away, and secondary accessor
//  USRs), the distinct implicit ones it skipped in the scanned files, the
//  records given a secondary accessor USR, and the records whose primary
//  USR is an Objective-C one (`c:`, `@objc` declarations such as XCTest's
//  classes and methods).
//

/// What the USR join counted.
public struct IndexDefinitions: Codable, Hashable, Sendable {
    /// Distinct definitions assigned to a record, as primary or secondary
    /// USR.
    public let joined: Int
    /// Distinct implicit function-like definitions skipped.
    public let implicit: Int
    /// Records with a secondary accessor USR.
    public let secondary: Int
    /// Records whose primary USR is an Objective-C USR.
    public let objc: Int

    /// Creates the counts. Fields are documented on their properties.
    public init(joined: Int, implicit: Int, secondary: Int, objc: Int) {
        self.joined = joined
        self.implicit = implicit
        self.secondary = secondary
        self.objc = objc
    }
}
