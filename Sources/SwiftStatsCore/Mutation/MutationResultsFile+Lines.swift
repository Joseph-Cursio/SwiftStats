//
//  MutationResultsFile+Lines.swift
//  SwiftStatsCore
//
//  The lines of a results file as SwiftStats decodes them (M6, design
//  §2): only the keys it reads, so unknown keys are ignored. A line
//  missing a key SwiftMutator always writes doesn't read, as it doesn't
//  for SwiftMutator's own reader (`RecordedResults`); a key it may leave
//  out reads as empty or absent.
//

extension MutationResultsFile {
    /// Any line's `kind`.
    struct KindLine: Decodable {
        /// The kind of record.
        let kind: String
    }

    /// A header's format version, read before the rest.
    struct VersionLine: Decodable {
        /// The header's format.
        let formatVersion: Int
    }

    /// What a mutant replaces, and with what.
    struct Snapshot: Decodable {
        /// The code before.
        let before: String
        /// The code after.
        let after: String
        /// What it does.
        let description: String
    }

    /// A test a log showed failing.
    struct FailedTest: Decodable {
        /// Its name.
        let name: String
    }

    /// Why a session tested a mutant again.
    struct RerunLine: Decodable {
        /// The reason.
        let because: String
    }

    /// A key's five parts, as lines and headers spell them.
    struct KeyLine: Decodable {
        /// The path.
        let path: String
        /// The line.
        let line: Int
        /// The column.
        let column: Int
        /// The occurrence.
        let occurrence: Int
        /// The operator.
        let mutationOperatorId: String

        /// The key.
        var key: MutantKey {
            MutantKey(path: path, operatorID: mutationOperatorId, line: line, column: column, occurrence: occurrence)
        }
    }

    /// A `mutant` line.
    struct MutantLine: Decodable {
        /// The session that tested it.
        let session: Int
        /// Its key.
        let key: MutantKey
        /// What it replaces.
        let snapshot: Snapshot
        /// The raw outcome.
        let outcome: String
        /// How its run ended.
        let endedBy: String
        /// The exit status of an `exited` run.
        let exitStatus: Int?
        /// How long its run took.
        let durationSeconds: Double?
        /// The tests its log showed failing; empty when it names none.
        let killedBy: [String]
        /// Whether its list is whole; not recorded when the line has no
        /// `killedBy`, which a survivor, a build error or an older session
        /// whose failed-test lines weren't reliable leaves out.
        let completeness: KillListCompleteness
        /// How many tests failed, uncapped.
        let failedTestCount: Int?
        /// Its file's SHA-256.
        let fileSHA256: String?
        /// Whether `--reuse` copied it.
        let reused: Bool
        /// Why the session tested it again.
        let rerun: RerunLine?
        /// Whether it was taken out of the build with others.
        let leftOutWithOthers: Bool
        /// Whether its block ran.
        let activated: MutantActivation

        /// Reads a `mutant` line.
        init(from decoder: any Decoder) throws {
            let container = try decoder.container(keyedBy: JSONKey.self)
            session = try container.decode(Int.self, forKey: "session")
            key = try KeyLine(from: decoder).key
            snapshot = try container.decode(Snapshot.self, forKey: "snapshot")
            outcome = try container.decode(String.self, forKey: "outcome")
            endedBy = try container.decode(String.self, forKey: "endedBy")
            exitStatus = try container.decodeIfPresent(Int.self, forKey: "exitStatus")
            durationSeconds = try container.decodeIfPresent(Double.self, forKey: "durationSeconds")
            killedBy = try container.decodeIfPresent([FailedTest].self, forKey: "killedBy")?.map(\.name) ?? []
            failedTestCount = try container.decodeIfPresent(Int.self, forKey: "failedTestCount")
            fileSHA256 = try container.decodeIfPresent(String.self, forKey: "fileSHA256")
            reused = container.contains("reusedFrom")
            rerun = try container.decodeIfPresent(RerunLine.self, forKey: "rerun")
            leftOutWithOthers = try container.decodeIfPresent(JSONFlag.self, forKey: "leftOutWithOthers")?.value == true
            activated = try MutantActivation(container.decodeIfPresent(JSONFlag.self, forKey: "activated"))
            completeness = KillListCompleteness(
                killedBy: killedBy,
                listed: container.contains("killedBy"),
                endedBy: endedBy,
                failedTestCount: failedTestCount
            )
        }
    }

    /// A `retired` line.
    struct RetiredLine: Decodable {
        /// The resumed session that wrote it.
        let session: Int
        /// The keys it retires.
        let keys: [KeyLine]
    }

    /// A `control` line.
    struct ControlLine: Decodable {
        /// Its session.
        let session: Int
        /// Its raw outcome.
        let outcome: String
    }

    /// An `end` line.
    struct EndLine: Decodable {
        /// Its session.
        let session: Int
        /// When it ended.
        let endedAt: String
        /// `finished`, `aborted` or `interrupted`.
        let reason: String
        /// The abort's code or the signal's name.
        let detail: String?
    }

    /// A `stopped` line.
    struct StoppedLine: Decodable {
        /// The step.
        let step: String
        /// Why it stopped.
        let reason: String
        /// The abort's code or the signal's name.
        let detail: String?
        /// The tests that failed; empty when the stop had no log.
        let failedTests: [String]
        /// How many failed, uncapped.
        let failedTestCount: Int?

        /// Reads a `stopped` line.
        init(from decoder: any Decoder) throws {
            let container = try decoder.container(keyedBy: JSONKey.self)
            step = try container.decode(String.self, forKey: "step")
            reason = try container.decode(String.self, forKey: "reason")
            detail = try container.decodeIfPresent(String.self, forKey: "detail")
            failedTests = try container.decodeIfPresent([FailedTest].self, forKey: "failedTests")?.map(\.name) ?? []
            failedTestCount = try container.decodeIfPresent(Int.self, forKey: "failedTestCount")
        }
    }
}
