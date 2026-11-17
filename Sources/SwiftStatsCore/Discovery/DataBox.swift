//
//  DataBox.swift
//  SwiftStatsCore
//
//  A mutable holder for bytes read on a helper thread.
//

import Foundation

/// Holds the bytes a helper thread reads, for the caller to collect after
/// joining it.
///
/// `@unchecked Sendable` is sound because `ProcessRunner` writes `data` once on
/// the reader thread and reads it only after that thread has finished.
final class DataBox: @unchecked Sendable {
    /// The bytes read so far.
    var data = Data()

    deinit {
        // Nothing to release: `data` is a value type.
    }
}
