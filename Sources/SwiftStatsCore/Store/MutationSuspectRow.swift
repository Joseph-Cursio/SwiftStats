//
//  MutationSuspectRow.swift
//  SwiftStatsCore
//
//  The `mutationSuspect` table (M6, design §5): one row per test a run
//  judged suspect, and why. A test is its name and file, as SwiftMutator
//  tells tests apart, so two rows of a run may share a name.
//

import GRDB

/// One suspect test of a snapshot's run.
struct MutationSuspectRow: Codable, Equatable, FetchableRecord, PersistableRecord {
    /// The table name.
    static let databaseTableName = "mutationSuspect"

    /// The snapshot.
    var snapshotId: Int64
    /// The run's ordinal.
    var run: Int
    /// The test's name.
    var name: String
    /// The file its issues were recorded in; none for an XCTest test.
    var file: String?
    /// Why it is suspect, by name.
    var why: String
    /// For `reach`: how many files with kills it failed in.
    var files: Int?
    /// For `reach`: how many files have a kill naming a test.
    var filesWithKills: Int?

    /// The suspect test this row records; it throws when its reason
    /// doesn't read.
    var test: MutationSuspectTest {
        get throws {
            MutationSuspectTest(
                name: name,
                file: file,
                run: run,
                why: try RowJSON.named(SuspectReason.self, from: why),
                files: files,
                filesWithKills: filesWithKills
            )
        }
    }

    /// The row for `test` in snapshot `snapshotId`.
    init(_ test: MutationSuspectTest, snapshotId: Int64) {
        self.snapshotId = snapshotId
        run = test.run
        name = test.name
        file = test.file
        why = test.why.rawValue
        files = test.files
        filesWithKills = test.filesWithKills
    }
}
