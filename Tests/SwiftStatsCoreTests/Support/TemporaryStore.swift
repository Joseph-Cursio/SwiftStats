//
//  TemporaryStore.swift
//  SwiftStatsCoreTests
//
//  A snapshot store in a temporary directory of its own, with what tests
//  need to look into it: its file, read with `sqlite3`, and a way to
//  remove it once checked.
//

import Foundation
@testable import SwiftStatsCore

/// A store in a temporary directory.
struct TemporaryStore {
    /// The store.
    let store: SnapshotStore
    /// Its database file.
    let url: URL
    /// The directory holding it.
    let directory: URL

    /// A new, empty store in a directory named after `prefix`.
    init(_ prefix: String) throws {
        directory = try SnapshotHarness.temporaryDirectory(prefix)
        url = directory.appendingPathComponent("stats.sqlite")
        store = try SnapshotStore(at: url)
    }

    /// `sqlite3`'s output for `statement` on the store's file.
    func query(_ statement: String) throws -> String {
        let output = try ProcessRunner.run(
            executable: "/usr/bin/sqlite3",
            arguments: [url.path, statement],
            in: directory
        )
        return String(bytes: output, encoding: .utf8) ?? ""
    }

    /// Removes the directory and the store in it.
    func remove() {
        try? FileManager.default.removeItem(at: directory)
    }
}
