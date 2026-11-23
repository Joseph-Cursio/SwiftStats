//
//  MutationWorkCopy.swift
//  SwiftStatsCore
//
//  The temporary copy SwiftMutator runs in (M6, design §1.2), made for
//  each run in `.swiftstats/mutation/work/` and removed after it, so its
//  side folders, which it writes beside the project, land in the ignored
//  folder too. With git, the copy is a shared clone of the package's
//  repository (no object copied, nothing in the source written), sparse
//  to the package's folder when the package isn't the repository's top
//  level, checked out at the commit the scan read, with the package's
//  changes against it, the files SwiftMutator lists even when git ignores
//  them and the work tree's `.swift-version`s above the package laid over
//  it. Outside git, or in a folder its repository ignores (where
//  SwiftMutator walks the package rather than asking git), it is a copy
//  of the package.
//  Either way every file the scan parsed is then checked against the
//  scan's hash, and one git checked out differently is copied from the
//  package, so the copy is the scanned tree, file for file. Only the
//  package's `.build` outlives a run, kept in `build-cache/` and renamed
//  into the copy and back. The copy is not registered for removal on an
//  interrupt, which would delete the build in it: the next run recovers a
//  leftover one instead.
//

import Foundation

/// A temporary copy of a package, made for one SwiftMutator run.
struct MutationWorkCopy: Sendable {
    /// The package's build folder, which the copy borrows from `build-cache/`.
    static let buildFolder = ".build"

    /// The folder holding the copy and SwiftMutator's side folders.
    let work: URL
    /// The copy of the package: the project SwiftMutator runs in.
    let project: URL
    /// How many scanned files the copy took from the package because git
    /// checked them out with other bytes.
    let fixedFiles: Int

    /// The project's path inside `work/` for the package at `packageRoot`
    /// in `git`: `<repository folder>/<package path>` when the copy is a
    /// clone, else the package folder's name.
    static func projectPath(packageRoot: URL, git: GitState) -> String {
        guard let top = clonedRepository(of: packageRoot, git: git) else {
            return packageRoot.standardizedFileURL.lastPathComponent
        }
        let name = top.lastPathComponent
        return git.packagePath.isEmpty ? name : name + "/" + git.packagePath
    }

    /// Makes the copy of the package at `packageRoot`, whose state is
    /// `git`, in `directory`'s `work/`, which must not exist. `scanned`
    /// maps each file the scan parsed (relative to the package root) to the
    /// SHA-256 it read; `ignored` lists files in the package (relative to
    /// its root) never copied, such as a store kept there. On a failure
    /// nothing is left in `work/` and `build-cache/` is as it was.
    static func make(
        packageRoot: URL,
        git: GitState,
        scanned: [String: String],
        ignoring ignored: [String],
        in directory: MutationDirectory
    ) throws(MutationFailure) -> Self {
        let folder = directory.work
        guard FileClone.exists(folder) == false else {
            throw MutationFailure(description: "a copy from an earlier run is still in .swiftstats/mutation/work")
        }
        let copy = folder.appendingPathComponent(projectPath(packageRoot: packageRoot, git: git))
        do throws(MutationFailure) {
            try created(folder)
            if let commit = git.commit, let top = clonedRepository(of: packageRoot, git: git) {
                let clone = folder.appendingPathComponent(top.lastPathComponent)
                try checkOut(commit, of: top, packagePath: git.packagePath, into: clone)
                try overlay(packageRoot, against: commit, ignoring: ignored, onto: copy)
                try overlayPins(of: top, packagePath: git.packagePath, into: clone)
            } else {
                try copyPackage(packageRoot, ignoring: ignored, to: copy)
            }
            let fixed = try fixHashes(scanned, of: packageRoot, in: copy)
            try borrowBuild(from: directory, into: copy)
            return Self(work: folder, project: copy, fixedFiles: fixed)
        } catch {
            try? FileClone.remove(folder)
            throw error
        }
    }

    /// Recovers what a run that didn't finish left in `directory`: the
    /// build in its copy of the package at `packageRoot` goes back to
    /// `build-cache/` unless one is there, then `work/` is removed. Whether
    /// there was a `work/`.
    @discardableResult
    static func recoverLeftover(
        packageRoot: URL,
        git: GitState,
        in directory: MutationDirectory
    ) throws(MutationFailure) -> Bool {
        let folder = directory.work
        guard FileClone.exists(folder) else {
            return false
        }
        let build = folder.appendingPathComponent(projectPath(packageRoot: packageRoot, git: git))
            .appendingPathComponent(buildFolder)
        do {
            if FileClone.isDirectory(build), FileClone.exists(directory.buildCache) == false {
                try FileClone.move(build, to: directory.buildCache)
            }
            try FileClone.remove(folder)
        } catch {
            throw failure("remove the copy left by an earlier run", error)
        }
        return true
    }

    /// The top level of the repository the copy of the package at
    /// `packageRoot`, whose state is `git`, clones: nil outside git, before
    /// the first commit, and when the package lies below the top level in
    /// a folder its repository ignores. Git lists none of the untracked
    /// files there, so SwiftMutator walks the package rather than asking
    /// git (`GitFileListing.isIgnoredByItsRepository` at b16642de), and the
    /// copy is a whole copy, as outside git.
    private static func clonedRepository(of packageRoot: URL, git: GitState) -> URL? {
        guard git.commit != nil,
              let top = GitReader.line(["rev-parse", "--show-toplevel"], in: packageRoot) else {
            return nil
        }
        // At the top level `.` reads as ignored when the repository ignores
        // everything, though git lists what it tracks; `--no-index` makes a
        // folder holding a file forced in read as ignored too, as there.
        if git.packagePath.isEmpty == false,
           GitReader.output(["check-ignore", "-q", "--no-index", "."], in: packageRoot) != nil {
            return nil
        }
        return URL(fileURLWithPath: top)
    }

    /// The failure of `action` (`could not <action>`) because of `error`,
    /// whose description names files by their names alone.
    static func failure(_ action: String, _ error: any Error) -> MutationFailure {
        MutationFailure(description: "could not \(action) (\(error.localizedDescription))")
    }

    /// Makes the folder at `url`.
    private static func created(_ url: URL) throws(MutationFailure) {
        do {
            try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        } catch {
            throw failure("make the copy's folder", error)
        }
    }

    /// Moves `directory`'s `build-cache/`, when there is one, to the
    /// copy's `.build`, replacing anything git checked out there.
    private static func borrowBuild(from directory: MutationDirectory, into project: URL) throws(MutationFailure) {
        guard FileClone.isDirectory(directory.buildCache) else {
            return
        }
        do {
            try FileClone.move(directory.buildCache, to: project.appendingPathComponent(buildFolder))
        } catch {
            throw failure("move build-cache into the copy", error)
        }
    }

    /// Ends the copy after a run: its build goes back to `directory`'s
    /// `build-cache/`, replacing any there, and `work/` is removed.
    func finish(in directory: MutationDirectory) throws(MutationFailure) {
        let build = project.appendingPathComponent(Self.buildFolder)
        do {
            if FileClone.isDirectory(build) {
                try FileClone.move(build, to: directory.buildCache)
            }
            try FileClone.remove(work)
        } catch {
            throw Self.failure("remove the copy after the run", error)
        }
    }
}
