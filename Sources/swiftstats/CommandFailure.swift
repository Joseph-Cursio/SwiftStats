//
//  CommandFailure.swift
//  swiftstats
//
//  How commands report failures: a wrong package path is a usage error
//  (exit 64, with the usage text); anything else is reported on standard
//  error with exit status 1.
//

import ArgumentParser
import Foundation
import SwiftStatsCore

/// Runs a command's body, turning SwiftStats errors into exits.
enum CommandFailure {
    /// `body`'s result, or the exit its error calls for.
    static func reporting<Result>(_ body: () throws -> Result) throws -> Result {
        do {
            return try body()
        } catch ScanError.notAPackage(let path) {
            throw ValidationError(ScanError.notAPackage(path).description)
        } catch let error as ScanError {
            throw fail(error.description)
        } catch let error as StoreError {
            throw fail(error.description)
        }
    }

    /// Writes `message` to standard error and returns the failure exit.
    static func fail(_ message: String) -> ExitCode {
        FileHandle.standardError.write(Data("Error: \(message)\n".utf8))
        return ExitCode.failure
    }

    /// Writes `data` to `output`, or to standard output when it is nil.
    static func write(_ data: Data, to output: String?) throws {
        if let output {
            try data.write(to: URL(fileURLWithPath: output))
        } else {
            FileHandle.standardOutput.write(data)
        }
    }
}
