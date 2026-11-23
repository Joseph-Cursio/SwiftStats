//
//  ScanError.swift
//  SwiftStatsCore
//
//  Errors that stop a scan outright. Problems with a single file are reported
//  as warnings in the scan output instead, so one bad file doesn't lose the
//  rest of the package.
//

/// A failure that prevents a scan from producing any output.
public enum ScanError: Error, Equatable, CustomStringConvertible {
    /// An external command exited non-zero: the command, its exit code and
    /// its standard error.
    case commandFailed(String, Int32, String)
    /// `.swiftstats.yml` could not be used: its path and the reason.
    case configurationInvalid(String, String)
    /// `swift package describe` output could not be decoded: the package
    /// path and the decoding error.
    case descriptionUnreadable(String, String)
    /// `scan --mutation` was refused before anything ran, for the reason
    /// given (M6).
    case mutationRefused(String)
    /// The given path is not a directory containing `Package.swift`.
    case notAPackage(String)

    /// A one-line explanation for the command line.
    public var description: String {
        switch self {
        case let .commandFailed(command, status, message):
            return "`\(command)` exited with status \(status): \(message)"
        case let .configurationInvalid(path, reason):
            return "\(path): \(reason)"

        case let .descriptionUnreadable(path, reason):
            return "could not read SwiftPM's description of \(path): \(reason)"
        case .mutationRefused(let reason):
            return "scan --mutation: \(reason)"
        case .notAPackage(let path):
            return "\(path) does not contain a Package.swift"
        }
    }
}
