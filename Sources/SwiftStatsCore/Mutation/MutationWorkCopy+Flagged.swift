//
//  MutationWorkCopy+Flagged.swift
//  SwiftStatsCore
//
//  The tracked files git may check out in the mutation collector's copy
//  with other bytes than the work tree holds, though it lists none of them
//  as changed (M6, design §1.2 step 4, as built): files marked
//  `skip-worktree` or `assume-unchanged` (a local override of
//  `Package.swift` hidden that way, say), whose edits git never reports,
//  and files with a `filter` attribute (LFS, whose checkout leaves
//  pointers, or git-crypt, whose filter's configuration lives in the
//  source's own `.git/config` and isn't cloned) or an `ident` attribute.
//  Each such file of the repository, the package's or not, that the work
//  tree holds and the copy holds otherwise is copied from the work tree
//  and counted with the files the hash check fixes, so the build and the
//  tests run on the bytes the user's do. Known limit: a repository-local
//  `core.autocrlf`, `core.eol` or other setting that changes a checkout
//  isn't cloned, and a file it changes that the scan didn't parse keeps
//  git's bytes in the copy; a parsed one is put right by the hash check.
//

import Foundation

extension MutationWorkCopy {
    /// How many characters start an entry of `git ls-files -v`: its tag
    /// and a space.
    private static let tagWidth = 2

    /// Copies into `clone`, a checkout of the repository at `top`, each
    /// tracked file git may have checked out with other bytes than the
    /// work tree holds, that the work tree holds and the copy holds
    /// otherwise; how many it copied.
    static func fixFlagged(of top: URL, in clone: URL) throws(MutationFailure) -> Int {
        var fixed = 0
        for path in try flaggedPaths(of: top) where isLeftOut(path, in: top) == false {
            let source = top.appendingPathComponent(path)
            let copied = clone.appendingPathComponent(path)
            guard FileClone.exists(source), holdsSame(source, as: copied) == false else {
                continue
            }
            try attempt(path) {
                try FileClone.copy(source, to: copied)
            }
            fixed += 1
        }
        return fixed
    }

    /// The tracked paths of the repository at `top` git may check out with
    /// other bytes and not list as changed: marked `skip-worktree` (`S`)
    /// or `assume-unchanged` (a lowercase tag) by `git ls-files -v`, or
    /// with a `filter` (set to anything) or `ident` attribute; sorted.
    static func flaggedPaths(of top: URL) throws(MutationFailure) -> [String] {
        let listing = ["--no-optional-locks", "ls-files", "-z"]
        let tagged = try paths("ls-files", listing + ["-v"], in: top, named: "<repository>")
            .compactMap { entry -> String? in
                guard let tag = entry.first, entry.dropFirst().first == " ",
                      tag.isLowercase || tag == "S" else {
                    return nil
                }
                return String(entry.dropFirst(Self.tagWidth))
            }
        // An exclusion of the files whose filter is unspecified keeps those
        // with any filter: no pathspec matches "set to anything".
        let filtered = try paths(
            "ls-files",
            listing + ["--", ".", ":(exclude,attr:!filter)"],
            in: top,
            named: "<repository>"
        )
        let identified = try paths("ls-files", listing + ["--", ":(attr:ident)"], in: top, named: "<repository>")
        return Set(tagged + filtered + identified).sorted()
    }

    /// Whether the files at `source` and `copied` hold the same: both links
    /// to the same path, or both files of the same bytes.
    private static func holdsSame(_ source: URL, as copied: URL) -> Bool {
        let files = FileManager.default
        let links = (
            try? files.destinationOfSymbolicLink(atPath: source.path),
            try? files.destinationOfSymbolicLink(atPath: copied.path)
        )
        if links.0 != nil || links.1 != nil {
            return links.0 == links.1
        }
        // A work tree file that can't be read is left as git checked it out.
        guard let size = Self.size(of: source) else {
            return true
        }
        guard Self.size(of: copied) == size else {
            return false
        }
        guard let held = try? Data(contentsOf: source) else {
            return true
        }
        return (try? Data(contentsOf: copied)) == held
    }

    /// The size in bytes of the file at `url`; nil when it can't be read.
    private static func size(of url: URL) -> Int? {
        (try? FileManager.default.attributesOfItem(atPath: url.path))?[.size] as? Int
    }
}
