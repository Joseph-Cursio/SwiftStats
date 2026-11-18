//
//  AdapterError.swift
//  SwiftStatsCore
//
//  Why an adapter couldn't read a tool's output. It fails that collector
//  (PRD §6.5), not the scan.
//

/// A tool's output the adapter couldn't use.
enum AdapterError: Error, Equatable, CustomStringConvertible {
    /// The output's schema version isn't the one the adapter reads.
    case unknownSchema(String, found: String, expected: Int)
    /// The output didn't decode: the collector and the decoding error.
    case unreadableOutput(String, String)

    /// A one-line explanation for the collector's status.
    var description: String {
        switch self {
        case let .unknownSchema(name, found, expected):
            return "\(name) wrote schemaVersion \(found); SwiftStats reads \(expected)"

        case let .unreadableOutput(name, reason):
            return "could not read \(name)'s output: \(reason)"
        }
    }
}
