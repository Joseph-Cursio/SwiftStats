//
//  SourcePaths.swift
//  SwiftStatsCore
//
//  The package's sources by real path (M7). The compiler, the index store
//  and outskirts give a source as an absolute real path: symbolic links
//  resolved and, on a case-insensitive volume, each name in the case the
//  disk holds (realpath(3)). The scan and the describe spell a source as
//  the package joins it, so a target directory or a file that is a
//  symbolic link keeps the link's spelling, and a manifest may spell a
//  path in another case than the disk. Every source is resolved once, as
//  `IndexStoreReader.realPath` resolves a path, and a tool's path is
//  resolved the same way before it is looked up, so the two sides meet
//  whatever the links or the case: the build output's placement, the unit
//  filter, the USR join and outskirts' file mapping all go through here.
//  The scanned files come first; the describe's other sources (a file a
//  `.swiftstats.yml` glob excludes, a target's non-Swift source) follow
//  at a lower priority, so a source the scan didn't parse still maps to
//  its manifest spelling, never to a real path the manifest doesn't name.
//  A path that is no source's real path is made relative to the root's
//  real path (as given, then resolved), or lies outside the root. One real
//  path reached under several spellings (a file two targets reach through
//  links) maps to the spelling in the target asked for, else the first in
//  code point order.
//

import Foundation

/// The package's sources, by real path.
struct SourcePaths: Sendable {
    /// A source: its path in the package as the scan or the describe
    /// spells it, and the target holding it.
    struct Source: Hashable, Sendable {
        /// The path in the package, as the scan or the describe spells it.
        let path: String
        /// The target's name.
        let target: String
    }

    /// The package root's real path, in NFC.
    let root: String
    /// Each source, by its real path in NFC; several in code point order
    /// of their paths.
    private let byRealPath: [String: [Source]]

    /// The sources `sources` of the package whose root's real path is
    /// `root`.
    init(root: String, sources: [Source]) {
        self.init(root: root, sources: sources, fallback: [])
    }

    /// The sources `sources` of the package whose root's real path is
    /// `root`, then `fallback`, which count only at a real path no source
    /// of `sources` resolves to.
    init(root: String, sources: [Source], fallback: [Source]) {
        self.root = root.precomposedStringWithCanonicalMapping
        let base = self.root.hasSuffix("/") ? self.root : self.root + "/"
        var resolved = Self.grouped(Set(sources), base: base)
        let spelled = Set(sources.map(\.path))
        // A fallback spelled as a source resolves where that source does.
        let others = Set(fallback.filter { spelled.contains($0.path) == false })
        for (real, group) in Self.grouped(others, base: base) where resolved[real] == nil {
            resolved[real] = group
        }
        byRealPath = resolved.mapValues { group in
            group.sorted { ($0.path, $0.target) < ($1.path, $1.target) }
        }
    }

    /// The scanned `files` of the package whose root's real path is `root`.
    init(root: String, files: [FileRecord]) {
        self.init(root: root, sources: files.map { Source(path: $0.path, target: $0.module) })
    }

    /// The scanned `files` of `package`, whose root's real path is `root`,
    /// then the describe's other sources (`sources(of:)`), which the scan
    /// didn't parse.
    init(root: String, files: [FileRecord], package: DescribedPackage) {
        self.init(
            root: root,
            sources: files.map { Source(path: $0.path, target: $0.module) },
            fallback: Self.sources(of: package)
        )
    }

    /// Every source of every target of `package`, joined as
    /// `TargetResolver` joins them, of the package whose root's real path
    /// is `root`.
    init(root: String, package: DescribedPackage) {
        self.init(root: root, sources: Self.sources(of: package))
    }

    /// Every source of every target of `package`, joined as
    /// `TargetResolver` joins them, in NFC.
    static func sources(of package: DescribedPackage) -> [Source] {
        var sources: [Source] = []
        for target in package.targets {
            let directory = TargetResolver.normalised(target.path)
            for source in target.sources {
                let path = TargetResolver.normalised(directory.isEmpty ? source : directory + "/" + source)
                sources.append(Source(path: path.precomposedStringWithCanonicalMapping, target: target.name))
            }
        }
        return sources
    }

    /// `sources`, each under `base` (the root's real path and a slash), by
    /// real path.
    private static func grouped(_ sources: Set<Source>, base: String) -> [String: [Source]] {
        var resolved: [String: [Source]] = [:]
        for source in sources {
            resolved[resolve(base + source.path), default: []].append(source)
        }
        return resolved
    }

    /// `path` (absolute) resolved as every path here is: its real path in
    /// NFC (`IndexStoreReader.realPath`).
    static func resolve(_ path: String) -> String {
        IndexStoreReader.realPath(path)
    }

    /// The path in the package of the source whose real path `path`
    /// resolves to: the one in `target` when it has one, else the first;
    /// nil when no source's.
    func source(at path: String, in target: String?) -> String? {
        guard let sources = byRealPath[Self.resolve(path)] else {
            return nil
        }
        return (sources.first { $0.target == target } ?? sources.first)?.path
    }

    /// Whether `path` resolves to the real path of a source of `target`.
    func isSource(_ path: String, of target: String) -> Bool {
        byRealPath[Self.resolve(path)]?.contains { $0.target == target } == true
    }

    /// `path` (absolute) as a path in the package: the source whose real
    /// path it resolves to (in `target` when it has one there), else
    /// relative to the root, as given and then resolved; nil when it lies
    /// outside the root.
    func packagePath(of path: String, in target: String?) -> String? {
        if let source = source(at: path, in: target) {
            return source
        }
        let prefix = root.hasSuffix("/") ? root : root + "/"
        for candidate in [path.precomposedStringWithCanonicalMapping, Self.resolve(path)]
        where candidate.hasPrefix(prefix) && candidate.count > prefix.count {
            return String(candidate.dropFirst(prefix.count))
        }
        return nil
    }
}
