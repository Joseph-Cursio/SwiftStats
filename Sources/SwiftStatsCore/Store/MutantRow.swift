//
//  MutantRow.swift
//  SwiftStatsCore
//
//  The `mutant` table (M6, design §5): one row per mutant of a snapshot,
//  dropped and unmapped ones included, in the report's order. The verdict
//  is held by name, `killedBy` as a JSON array of names; `activated`, `killedByComplete` and
//  `suspectOnly` are 1, 0, or null when not recorded or not judged; the
//  anchor is null when there is none.
//

import GRDB

/// One mutant of a snapshot.
struct MutantRow: Codable, Equatable, FetchableRecord, PersistableRecord {
    /// The columns; `operator` is a keyword.
    private enum CodingKeys: String, CodingKey {
        case snapshotId
        case ordinal
        case path
        case line
        case column
        case occurrence
        case operatorID = "operator"
        case anchorLine
        case anchorColumn
        case verdict
        case outcome
        case activated
        case endedBy
        case exitStatus
        case killedBy
        case killedByComplete
        case failedTestCount
        case suspectOnly
        case fileSHA256
        case before
        case after
        case description
        case session
        case durationSeconds
        case run
        case carried
        case reused
        case rerunBecause
        case place
        case owner
        case reason
    }

    /// The table name.
    static let databaseTableName = "mutant"

    /// The snapshot.
    var snapshotId: Int64
    /// The mutant's position in the report, from 0.
    var ordinal: Int
    /// Its file's path, as SwiftMutator records it.
    var path: String
    /// SwiftMutator's line.
    var line: Int
    /// SwiftMutator's column.
    var column: Int
    /// Its occurrence.
    var occurrence: Int
    /// Its operator's id.
    var operatorID: String
    /// Its anchor's line; null without an anchor.
    var anchorLine: Int?
    /// Its anchor's column; null without an anchor.
    var anchorColumn: Int?
    /// Its verdict, by name.
    var verdict: String
    /// The raw outcome.
    var outcome: String?
    /// Whether its block ran: 1, 0 or null.
    var activated: Int?
    /// How its run ended.
    var endedBy: String?
    /// The exit status of an `exited` run.
    var exitStatus: Int?
    /// The tests named failing, as a JSON array.
    var killedBy: String
    /// Whether that list is whole: 1, 0 or null.
    var killedByComplete: Int?
    /// How many distinct tests failed.
    var failedTestCount: Int?
    /// Whether only suspect tests killed it: 1, 0 or null.
    var suspectOnly: Int?
    /// Its file's SHA-256 as the run tested it.
    var fileSHA256: String?
    /// The code it replaces.
    var before: String
    /// The code it puts in its place.
    var after: String
    /// What it does.
    var description: String
    /// The session that tested it.
    var session: Int?
    /// How long its run took, in seconds.
    var durationSeconds: Double?
    /// The ordinal of the run that tested it.
    var run: Int
    /// Whether it came from an earlier snapshot.
    var carried: Bool
    /// Whether SwiftMutator reused its result.
    var reused: Bool
    /// Why it was tested again.
    var rerunBecause: String?
    /// Where it went.
    var place: MutationPlace
    /// What it went to.
    var owner: String?
    /// Why it is unmapped, or the class that dropped it.
    var reason: String?

    /// The mutant this row records; it throws when its verdict or
    /// `killedBy` doesn't read.
    var mutant: Mutant {
        get throws {
            Mutant(
                path: path,
                line: line,
                column: column,
                occurrence: occurrence,
                operatorID: operatorID,
                anchor: anchor,
                verdict: try RowJSON.named(MutationVerdict.self, from: verdict),
                outcome: outcome,
                activated: Self.flag(activated),
                endedBy: endedBy,
                exitStatus: exitStatus,
                killedBy: try RowJSON.decoded([String].self, from: killedBy),
                killedByComplete: Self.flag(killedByComplete),
                failedTestCount: failedTestCount,
                suspectOnly: Self.flag(suspectOnly),
                fileSHA256: fileSHA256,
                before: before,
                after: after,
                description: description,
                run: run,
                session: session,
                durationSeconds: durationSeconds,
                carried: carried,
                reused: reused,
                rerun: rerunBecause,
                place: place,
                owner: owner,
                reason: reason
            )
        }
    }

    /// The anchor these columns hold; nil unless both are set.
    private var anchor: SourcePosition? {
        guard let anchorLine, let anchorColumn else {
            return nil
        }
        return SourcePosition(line: anchorLine, column: anchorColumn)
    }

    /// The row for `mutant`, the `ordinal`th of the report, in snapshot
    /// `snapshotId`.
    init(_ mutant: Mutant, ordinal: Int, snapshotId: Int64) {
        self.snapshotId = snapshotId
        self.ordinal = ordinal
        path = mutant.path
        line = mutant.line
        column = mutant.column
        occurrence = mutant.occurrence
        operatorID = mutant.operatorID
        anchorLine = mutant.anchor?.line
        anchorColumn = mutant.anchor?.column
        verdict = mutant.verdict.rawValue
        outcome = mutant.outcome
        activated = Self.column(mutant.activated)
        endedBy = mutant.endedBy
        exitStatus = mutant.exitStatus
        killedBy = RowJSON.text(mutant.killedBy)
        killedByComplete = Self.column(mutant.killedByComplete)
        failedTestCount = mutant.failedTestCount
        suspectOnly = Self.column(mutant.suspectOnly)
        fileSHA256 = mutant.fileSHA256
        before = mutant.before
        after = mutant.after
        description = mutant.description
        session = mutant.session
        durationSeconds = mutant.durationSeconds
        run = mutant.run
        carried = mutant.carried
        reused = mutant.reused
        rerunBecause = mutant.rerun
        place = mutant.place
        owner = mutant.owner
        reason = mutant.reason
    }

    /// `flag` as a column: 1, 0, or null when there is none.
    private static func column(_ flag: JSONFlag?) -> Int? {
        flag.map { $0.value ? 1 : 0 }
    }

    /// The flag a column holding `value` records: true for any number but
    /// 0, none for null.
    private static func flag(_ value: Int?) -> JSONFlag? {
        value.map { JSONFlag($0 != 0) }
    }
}
