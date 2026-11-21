//
//  MarkerVerdict.swift
//  SwiftStatsCore
//
//  What coverage says of one risk marker (M5, risky + untested): a test
//  ran it, none did, or coverage can't say, and why not.
//

/// The verdict on one risk marker.
enum MarkerVerdict: Hashable {
    /// Coverage can't say, for the reason given.
    case noData(String)
    /// A test ran it; on a line that ran while holding a region that
    /// didn't, when `partlyRun` is set.
    case tested(partlyRun: Bool)
    /// No test ran it.
    case untested

    /// Its function has no coverage data.
    static let functionWithoutData = "in a function with no coverage data"
    /// Its line is in an inactive `#if` branch.
    static let inactive = "in an inactive #if branch"
    /// Its type's functions have no coverage data, whatever is attached
    /// to the type.
    static let typeWithoutData = "on a type with no coverage data"
    /// Its line holds no code region, in a function that ran: a signature,
    /// a type annotation, a default argument.
    static let signature = "on a line with no code region in a function that ran"
    /// Its file has no line data: nothing in it holds a code region.
    static let fileWithoutData = "in a file with no coverage data"
    /// Its line holds no code region, outside functions: a stored property
    /// without an initialiser, a static or global initialiser.
    static let declaration = "on a line with no code region outside functions"
    /// The tool gave no line.
    static let noLine = "with no line"
}
