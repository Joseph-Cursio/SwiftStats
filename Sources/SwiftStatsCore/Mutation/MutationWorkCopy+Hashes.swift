//
//  MutationWorkCopy+Hashes.swift
//  SwiftStatsCore
//
//  The mutation collector's copy checked against the scan (M6, design §1.2
//  step 4), before anything is built in it: every file the scan parsed
//  must hold, in the copy, the bytes whose SHA-256 the scan recorded.
//  Git can check a file out with other bytes and list nothing as changed
//  (a repository-local `core.autocrlf` or an `eol=crlf` attribute, a
//  smudge filter, LFS, `ident`, `skip-worktree` or `assume-unchanged`);
//  such a file is copied from the package and counted. (A file the scan
//  didn't parse is checked only when git can say it may differ:
//  `MutationWorkCopy+Flagged.swift`.) A file the package no longer holds
//  as the scan read it, because it was edited during the scan, fails the
//  check naming it, so stale results are never mapped. A resumed run
//  checks its kept copy again the same way.
//

import Foundation

extension MutationWorkCopy {
    /// Makes each file of `scanned` (paths relative to the package root,
    /// mapped to the SHA-256 the scan read) in `project` hold the bytes the
    /// scan read, copying from the package at `packageRoot` the ones that
    /// differ, and returns how many it copied.
    static func fixHashes(
        _ scanned: [String: String],
        of packageRoot: URL,
        in project: URL
    ) throws(MutationFailure) -> Int {
        var fixed = 0
        for (path, hash) in scanned.sorted(by: { $0.key < $1.key }) {
            let copied = project.appendingPathComponent(path)
            guard ContentHash.sha256(ofFileAt: copied) != hash else {
                continue
            }
            guard let data = try? Data(contentsOf: packageRoot.appendingPathComponent(path)),
                  ContentHash.sha256(data) == hash else {
                throw MutationFailure(description: "\(path) changed after the scan read it; scan again")
            }
            do {
                try FileClone.write(data, to: copied)
            } catch {
                throw failure("copy \(path) into the copy", error)
            }
            guard ContentHash.sha256(ofFileAt: copied) == hash else {
                throw MutationFailure(description: "the copy of \(path) doesn't hold the bytes the scan read")
            }
            fixed += 1
        }
        return fixed
    }
}
