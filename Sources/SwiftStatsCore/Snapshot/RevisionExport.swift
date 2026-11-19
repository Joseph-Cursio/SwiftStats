//
//  RevisionExport.swift
//  SwiftStatsCore
//
//  A package as it was at a past commit (PRD §10, diff): checked out from a
//  temporary index into a temporary directory. That leaves no state in the
//  repository, unlike a worktree, and keeps every tracked file, unlike
//  `git archive`, which drops `export-ignore` paths and rewrites
//  `export-subst` files.
//

import Foundation

/// Exports a package directory at a commit.
enum RevisionExport {
    /// The commit `revision` names, so an annotated tag names its commit;
    /// nil when it names none.
    static func commit(of revision: String, in directory: URL) -> String? {
        GitReader.line(["rev-parse", "--verify", "--quiet", "\(revision)^{commit}"], in: directory)
    }

    /// Exports the package at `packagePath` (from the repository's top
    /// level) as of `commit` into a new temporary directory and returns it;
    /// the caller removes it. Throws when the package isn't there at that
    /// commit. Submodules are not exported.
    static func export(commit: String, packagePath: String, from directory: URL) throws -> URL {
        let tree = packagePath.isEmpty ? commit : "\(commit):\(packagePath)"
        let manifest = packagePath.isEmpty ? "\(commit):Package.swift" : "\(commit):\(packagePath)/Package.swift"
        guard GitReader.output(["cat-file", "-e", manifest], in: directory) != nil else {
            throw ScanError.notAPackage("\(packagePath.isEmpty ? "." : packagePath) at \(commit)")
        }
        // Run from the top level: from a subdirectory, `checkout-index`
        // keeps only paths under that subdirectory, which a tree's paths are not.
        guard let topPath = GitReader.line(["rev-parse", "--show-toplevel"], in: directory) else {
            throw ScanError.notAPackage("\(directory.path), which is not in a git repository")
        }
        let top = URL(fileURLWithPath: topPath)
        let work = FileManager.default.temporaryDirectory.appendingPathComponent("SwiftStats-\(UUID().uuidString)")
        let target = work.appendingPathComponent("package")
        let index = work.appendingPathComponent("index")
        do {
            try FileManager.default.createDirectory(at: target, withIntermediateDirectories: true)
            let environment = ["GIT_INDEX_FILE": index.path]
            _ = try ProcessRunner.run(
                executable: GitReader.git,
                arguments: ["read-tree", tree],
                in: top,
                environment: environment
            )
            _ = try ProcessRunner.run(
                executable: GitReader.git,
                arguments: ["checkout-index", "--all", "--prefix=\(target.path)/"],
                in: top,
                environment: environment
            )
            try FileManager.default.removeItem(at: index)
        } catch {
            try? FileManager.default.removeItem(at: work)
            throw error
        }
        return target
    }

    /// The directory to remove once the export at `package` is scanned.
    static func workDirectory(of package: URL) -> URL {
        package.deletingLastPathComponent()
    }
}
