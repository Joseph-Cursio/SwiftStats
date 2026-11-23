//
//  MutationResultsFile+Header.swift
//  SwiftStatsCore
//
//  A results file's `header` line as SwiftStats decodes it (M6, design
//  §2 items 4, 6, 10 and 11): the keys a session's facts, tree and
//  not-covered mutants come from. Whether `mutantsNotCovered` is present
//  matters apart from its entries: absent, with coverage on, the session
//  doesn't list code no test ran.
//

extension MutationResultsFile {
    /// A header's `provenance`, as far as it is read.
    struct ProvenanceLine: Decodable {
        /// SwiftMutator's version.
        let version: String
        /// Its executable's SHA-256.
        let executableSHA256: String?
        /// The test command's version text.
        let testCommandVersion: String?
        /// A wrapper test command's SHA-256.
        let testExecutableSHA256: String?
        /// The SDK environment.
        let environment: [String: String]

        /// Reads a header's `provenance`.
        init(from decoder: any Decoder) throws {
            let container = try decoder.container(keyedBy: JSONKey.self)
            let build = try container.nestedContainer(keyedBy: JSONKey.self, forKey: "swiftMutator")
            version = try build.decode(String.self, forKey: "version")
            executableSHA256 = try build.decodeIfPresent(String.self, forKey: "executableSHA256")
            guard container.contains("toolchain") else {
                testCommandVersion = nil
                testExecutableSHA256 = nil
                environment = [:]
                return
            }
            let toolchain = try container.nestedContainer(keyedBy: JSONKey.self, forKey: "toolchain")
            testCommandVersion = try toolchain.decodeIfPresent(String.self, forKey: "testCommandVersion")
            testExecutableSHA256 = try toolchain.decodeIfPresent(String.self, forKey: "testExecutableSHA256")
            environment = try toolchain.decodeIfPresent([String: String].self, forKey: "environment") ?? [:]
        }
    }

    /// A whole tree.
    struct ProjectLine: Decodable {
        /// Each file's hash by path.
        let files: [String: String]
        /// The tree's hash.
        let treeSHA256: String
    }

    /// A tree as what changed since an earlier one.
    struct ProjectDeltaLine: Decodable {
        /// The earlier tree's hash.
        let baseTreeSHA256: String
        /// The files added or changed.
        let files: [String: String]
        /// The paths removed.
        let removed: [String]
        /// The tree it makes.
        let treeSHA256: String
    }

    /// A file a `--since` run chose.
    struct ChangedFileLine: Decodable {
        /// Its path.
        let path: String
        /// Its hash.
        let sha256: String

        /// The file.
        var file: MutationSince.File {
            MutationSince.File(path: path, sha256: sha256)
        }
    }

    /// What a `--since` run chose.
    struct SinceLine: Decodable {
        /// The choice.
        let since: MutationSince

        /// Reads a header's `since`.
        init(from decoder: any Decoder) throws {
            let container = try decoder.container(keyedBy: JSONKey.self)
            since = try MutationSince(
                ref: container.decode(String.self, forKey: "ref"),
                commit: container.decode(String.self, forKey: "commit"),
                mergeBase: container.decode(String.self, forKey: "mergeBase"),
                files: container.decode([ChangedFileLine].self, forKey: "files").map(\.file),
                foldersNotCompared: container.decodeIfPresent([String].self, forKey: "foldersNotCompared") ?? []
            )
        }
    }

    /// A mutant of code no test ran.
    struct NotCoveredLine: Decodable {
        /// Its key.
        let key: MutantKey
        /// What it would replace.
        let snapshot: Snapshot

        /// Reads an entry of `mutantsNotCovered`.
        init(from decoder: any Decoder) throws {
            key = try KeyLine(from: decoder).key
            snapshot = try decoder.container(keyedBy: JSONKey.self).decode(Snapshot.self, forKey: "snapshot")
        }
    }

    /// A `header` line.
    struct HeaderLine: Decodable {
        /// The format.
        let formatVersion: Int
        /// The session's number.
        let session: Int
        /// When mutation testing started.
        let startedAt: String
        /// Where the results came from.
        let provenance: ProvenanceLine
        /// The operators, sorted.
        let operators: [String]
        /// Whether coverage was off.
        let skipCoverage: Bool
        /// Mutants tested at once.
        let workers: Int
        /// The time limit per mutant.
        let timeoutSeconds: Double?
        /// Whether a mutant's tests stop at the first failure.
        let stopsAtFirstFailure: Bool
        /// Mutants discovered.
        let mutantsDiscovered: Int
        /// Mutants dropped.
        let mutantsDropped: Int?
        /// The whole tree.
        let project: ProjectLine?
        /// The tree as a change.
        let projectDelta: ProjectDeltaLine?
        /// What a `--since` run chose.
        let since: MutationSince?
        /// Whether `mutantsNotCovered` is present.
        let listsNotCovered: Bool
        /// The mutants of code no test ran; empty when absent.
        let notCovered: [NotCoveredLine]

        /// Reads a `header` line.
        init(from decoder: any Decoder) throws {
            let container = try decoder.container(keyedBy: JSONKey.self)
            formatVersion = try container.decode(Int.self, forKey: "formatVersion")
            session = try container.decode(Int.self, forKey: "session")
            startedAt = try container.decode(String.self, forKey: "startedAt")
            provenance = try container.decode(ProvenanceLine.self, forKey: "provenance")
            operators = try container.decode([String].self, forKey: "operators")
            skipCoverage = try container.decode(Bool.self, forKey: "skipCoverage")
            workers = try container.decode(Int.self, forKey: "workers")
            timeoutSeconds = try container.decodeIfPresent(Double.self, forKey: "timeoutSeconds")
            stopsAtFirstFailure = try container.decode(Bool.self, forKey: "stopsAtFirstFailure")
            mutantsDiscovered = try container.decode(Int.self, forKey: "mutantsDiscovered")
            mutantsDropped = try container.decodeIfPresent(Int.self, forKey: "mutantsDropped")
            project = try container.decodeIfPresent(ProjectLine.self, forKey: "project")
            projectDelta = try container.decodeIfPresent(ProjectDeltaLine.self, forKey: "projectDelta")
            since = try container.decodeIfPresent(SinceLine.self, forKey: "since")?.since
            listsNotCovered = container.contains("mutantsNotCovered")
            notCovered = try container.decodeIfPresent([NotCoveredLine].self, forKey: "mutantsNotCovered") ?? []
        }
    }
}
