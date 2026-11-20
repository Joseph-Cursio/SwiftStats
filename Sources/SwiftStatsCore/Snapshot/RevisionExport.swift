//
//  RevisionExport.swift
//  SwiftStatsCore
//
//  A package as it was at a past commit (PRD §10, diff): checked out from a
//  temporary index into a temporary directory. That leaves no state in the
//  repository, unlike a worktree, and keeps every tracked file, unlike
//  `git archive`, which drops `export-ignore` paths and rewrites
//  `export-subst` files. A nested package gets the nearest toolchain pin
//  above it in the repository, written just above the export, so swiftly
//  picks the toolchain it would in the working tree.
//

import Foundation

/// Exports a package directory at a commit.
enum RevisionExport {
    /// The toolchain pin swiftly reads.
    private static let toolchainPinName = ".swift-version"

    /// The commit `revision` names, so an annotated tag names its commit;
    /// nil when it names none.
    static func commit(of revision: String, in directory: URL) -> String? {
        GitReader.line(["rev-parse", "--verify", "--quiet", "\(revision)^{commit}"], in: directory)
    }

    /// Exports the package at `packagePath` (from the repository's top
    /// level) as of `commit` into a new temporary directory and returns it,
    /// with the nearest `.swift-version` above the package at that commit
    /// in the directory above it; the caller removes that directory. Throws
    /// when the package isn't there at that commit. Submodules are not
    /// exported.
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
            if let pin = toolchainPin(above: packagePath, at: commit, in: top) {
                try pin.write(to: work.appendingPathComponent(toolchainPinName))
            }
        } catch {
            try? FileManager.default.removeItem(at: work)
            throw error
        }
        return target
    }

    /// The contents of the nearest `.swift-version` in a directory above
    /// `packagePath` as of `commit`; nil for a package at the top level or
    /// when there is none.
    private static func toolchainPin(above packagePath: String, at commit: String, in top: URL) -> Data? {
        guard packagePath.isEmpty == false else {
            return nil
        }
        var directories = packagePath.split(separator: "/").dropLast().map(String.init)
        while true {
            let pin = (directories + [toolchainPinName]).joined(separator: "/")
            if let data = GitReader.output(["cat-file", "blob", "\(commit):\(pin)"], in: top) {
                return data
            }
            guard directories.popLast() != nil else {
                return nil
            }
        }
    }

    /// The directory to remove once the export at `package` is scanned.
    static func workDirectory(of package: URL) -> URL {
        package.deletingLastPathComponent()
    }
}
