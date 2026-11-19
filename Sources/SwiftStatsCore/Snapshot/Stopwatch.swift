//
//  Stopwatch.swift
//  SwiftStatsCore
//
//  Wall-clock run times for collectors (PRD §6.2), kept out of the scan JSON
//  so it stays byte-identical between runs.
//

/// Times a piece of work.
enum Stopwatch {
    /// Milliseconds in a second.
    private static let millisecondsPerSecond: Int64 = 1_000
    /// Attoseconds in a millisecond.
    private static let attosecondsPerMillisecond: Int64 = 1_000_000_000_000_000

    /// `body`'s result and how long it took, in whole milliseconds.
    static func time<Result>(_ body: () throws -> Result) rethrows -> (result: Result, milliseconds: Int) {
        let start = ContinuousClock.now
        let result = try body()
        let elapsed = start.duration(to: .now).components
        let milliseconds = elapsed.seconds * millisecondsPerSecond + elapsed.attoseconds / attosecondsPerMillisecond
        return (result, Int(milliseconds))
    }
}
