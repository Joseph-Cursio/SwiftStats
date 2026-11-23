//
//  MutationFixture.swift
//  SwiftStatsCoreTests
//
//  SwiftMutator's recorded runs (M6, design §11), made by
//  `Scripts/record-mutation-fixture.sh`: the Coverage fixture's `full` case
//  and the Mutation fixture's `full`, `since`, `tests-only`,
//  `since-unlisted`, `stopped`, `interrupted` and `resumed`, in each
//  fixture's `Recorded/mutation/<case>/`. And the fixture's git repository
//  built as the script builds it, so its commits have the SHAs the
//  recordings name: the fixture's files (but `Recorded/`, `Patches/` and
//  build folders) with a `.gitignore`, committed on `main` as "Fixture"
//  dated 2026-01-01T00:00:00Z, and each `Patches/<patch>.patch` a branch
//  `<patch>` of one commit, "<patch>", dated a day later, with no global or
//  system git configuration.
//

import Foundation
@testable import SwiftStatsCore

/// The recorded SwiftMutator runs and their fixtures' repositories.
enum MutationFixture {
    /// A fixture's repository, built as the recording script builds it.
    struct Repository {
        /// Its root, the package.
        let root: URL
        /// Each branch's commit.
        let commits: [String: String]

        /// Removes the repository.
        func remove() {
            try? FileManager.default.removeItem(at: root)
        }

        /// Checks out `branch`.
        func checkOut(_ branch: String) throws {
            try MutationFixture.git(["checkout", "--quiet", branch], in: root, day: 0)
        }
    }

    /// The Mutation fixture.
    static let directory = fixtures.appendingPathComponent("Mutation")
    /// The Coverage fixture.
    static let coverageDirectory = fixtures.appendingPathComponent("Coverage")
    /// The `.gitignore` the repositories hold.
    static let gitignore = ".build/\n.swiftpm/\n"
    /// The folders at a fixture's top its repository leaves out.
    static let leftOutAtTop: Set<String> = ["Patches", "Recorded"]
    /// The names its repository leaves out at any depth.
    static let leftOut: Set<String> = [".DS_Store", ".build", ".swiftpm", ".swiftstats"]
    /// Seconds from 1970 to 2026-01-01T00:00:00Z, the date of `main`.
    static let dayZero = 1_767_225_600
    /// Seconds in a day, after which each patch's branch is dated.
    static let day = 86_400
    /// The columns of a `commits.txt` line: branch and commit.
    static let commitsColumns = 2
    /// The day each patch's branch is dated.
    static let patchDay = 1

    /// `Tests/Fixtures`.
    private static let fixtures = URL(fileURLWithPath: #filePath)
        .deletingLastPathComponent()
        .deletingLastPathComponent()
        .deletingLastPathComponent()
        .appendingPathComponent("Fixtures")

    /// The folder of `fixture`'s recorded case `name`.
    static func recorded(_ name: String, in fixture: URL) -> URL {
        fixture.appendingPathComponent("Recorded/mutation/\(name)")
    }

    /// The text of `file` in `fixture`'s recorded case `name`.
    static func text(_ file: String, of name: String, in fixture: URL) throws -> String {
        try String(contentsOf: recorded(name, in: fixture).appendingPathComponent(file), encoding: .utf8)
    }

    /// The bytes of `file` in `fixture`'s recorded case `name`.
    static func data(_ file: String, of name: String, in fixture: URL) throws -> Data {
        try Data(contentsOf: recorded(name, in: fixture).appendingPathComponent(file))
    }

    /// The results `fixture`'s recorded case `name` holds, read.
    static func contents(of name: String, in fixture: URL) throws -> MutationResultsFile.Contents {
        try MutationResultsFile.read(data("results.jsonl", of: name, in: fixture))
    }

    /// The results of `fixture`'s recorded case `name`, which must hold
    /// results.
    static func results(of name: String, in fixture: URL) throws -> MutationResults {
        guard case .results(let results) = try contents(of: name, in: fixture) else {
            throw MutationFailure(description: "\(name) holds no results")
        }
        return results
    }

    /// Each branch's commit as `fixture`'s `commits.txt` records it.
    static func recordedCommits(in fixture: URL) throws -> [String: String] {
        let text = try String(
            contentsOf: fixture.appendingPathComponent("Recorded/mutation/commits.txt"),
            encoding: .utf8
        )
        var commits: [String: String] = [:]
        for line in text.split(separator: "\n") {
            let parts = line.split(separator: " ")
            if parts.count == Self.commitsColumns {
                commits[String(parts[0])] = String(parts[1])
            }
        }
        return commits
    }

    /// `fixture`'s repository in a temporary directory, built as the
    /// recording script builds it, `main` checked out; removed again if it
    /// can't be made.
    static func repository(of fixture: URL) throws -> Repository {
        let root = try SnapshotHarness.temporaryDirectory("MutationFixture")
        do {
            try copyFiles(of: fixture, into: root)
            try gitignore.write(to: root.appendingPathComponent(".gitignore"), atomically: true, encoding: .utf8)
            try git(["init", "--quiet", "--initial-branch=main"], in: root, day: 0)
            try git(["add", "--all"], in: root, day: 0)
            try git(["commit", "--quiet", "--message", "Fixture"], in: root, day: 0)
            var commits = try ["main": git(["rev-parse", "main"], in: root, day: 0)]
            let patches = (try? FileManager.default.contentsOfDirectory(
                at: fixture.appendingPathComponent("Patches"),
                includingPropertiesForKeys: nil
            )) ?? []
            for patch in patches.filter({ $0.pathExtension == "patch" }) {
                let branch = patch.deletingPathExtension().lastPathComponent
                try git(["checkout", "--quiet", "-b", branch, "main"], in: root, day: Self.patchDay)
                try git(["apply", "--index", patch.path], in: root, day: Self.patchDay)
                try git(["commit", "--quiet", "--message", branch], in: root, day: Self.patchDay)
                commits[branch] = try git(["rev-parse", "HEAD"], in: root, day: Self.patchDay)
                try git(["checkout", "--quiet", "main"], in: root, day: Self.patchDay)
            }
            return Repository(root: root, commits: commits)
        } catch {
            try? FileManager.default.removeItem(at: root)
            throw error
        }
    }

    /// Runs git in `directory` with no global or system configuration,
    /// as the fixture's author and committer, dated `day` days after day
    /// zero; its output, trimmed.
    @discardableResult
    static func git(_ arguments: [String], in directory: URL, day: Int) throws -> String {
        let date = "@\(dayZero + day * Self.day) +0000"
        let environment = [
            "GIT_CONFIG_GLOBAL": "/dev/null",
            "GIT_CONFIG_NOSYSTEM": "1",
            "GIT_AUTHOR_NAME": "SwiftStats Fixture",
            "GIT_AUTHOR_EMAIL": "fixture@example.invalid",
            "GIT_COMMITTER_NAME": "SwiftStats Fixture",
            "GIT_COMMITTER_EMAIL": "fixture@example.invalid",
            "GIT_AUTHOR_DATE": date,
            "GIT_COMMITTER_DATE": date
        ]
        let data = try ProcessRunner.run(
            executable: "/usr/bin/git",
            arguments: arguments,
            in: directory,
            environment: environment
        )
        return String(bytes: data, encoding: .utf8)?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
    }

    /// Copies `fixture`'s regular files into `root`, but `leftOutAtTop`
    /// and, at any depth, `leftOut`, as the script's `find ... -prune -o
    /// -type f` picks them: symbolic links and empty folders aren't copied.
    private static func copyFiles(of fixture: URL, into root: URL) throws {
        let manager = FileManager.default
        guard let entries = manager.enumerator(atPath: fixture.path) else {
            return
        }
        while let path = entries.nextObject() as? String {
            let type = entries.fileAttributes?[.type] as? FileAttributeType
            let name = URL(fileURLWithPath: path).lastPathComponent
            if leftOut.contains(name) || (path == name && leftOutAtTop.contains(name)) {
                if type == .typeDirectory {
                    entries.skipDescendants()
                }
                continue
            }
            guard type == .typeRegular else {
                continue
            }
            let target = root.appendingPathComponent(path)
            try manager.createDirectory(at: target.deletingLastPathComponent(), withIntermediateDirectories: true)
            try manager.copyItem(at: fixture.appendingPathComponent(path), to: target)
        }
    }
}
