//
//  ProcessTermination.swift
//  SwiftStatsCore
//
//  How a finished command ended: by exiting with a status, or by a signal
//  it didn't handle. SwiftMutator ends an interrupted run by raising the
//  signal again once it has stopped (M6, design §1.5), so its collector
//  tells the two apart, as Foundation's `terminationReason` does.
//

import Foundation

/// How a command ended.
enum ProcessTermination: Equatable, Sendable {
    /// It exited with this status.
    case exited(Int32)
    /// A signal of this number ended it.
    case signalled(Int32)

    /// How `process`, which has exited, ended.
    init(_ process: Process) {
        switch process.terminationReason {
        case .uncaughtSignal:
            self = .signalled(process.terminationStatus)

        case .exit:
            self = .exited(process.terminationStatus)

        @unknown default:
            self = .exited(process.terminationStatus)
        }
    }
}
