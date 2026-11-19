//
//  ModuleMap.swift
//  SwiftStatsCore
//
//  Which module a package path belongs to and whether it is test code
//  (PRD §7.13). A file the analysed commit holds counts only when a target
//  of the scan compiles it, so fixtures, files a target excludes and files
//  of commented-out targets are not package code. Only an old path, one the
//  analysed commit no longer holds, is placed by the target directories and
//  the `Sources/<X>/` and `Tests/<X>/` convention for past layouts.
//

/// Which module a package path belongs to, and whether it is test code.
struct ModuleMap: Sendable {
    /// Where a file is: its module and whether it is test code.
    typealias Place = (module: String, isTest: Bool)

    /// One target directory.
    private struct Entry: Sendable {
        let directory: String
        let module: String
        let isTest: Bool
    }

    /// The path parts of a conventional `Sources/<X>/<file>` or `Tests/<X>/<file>`.
    private static let conventionalPartCount = 3

    /// The targets, longest directory first.
    private let entries: [Entry]
    /// The files the scan's targets compile, with their places.
    private let compiled: [String: Entry]
    /// The paths the analysed commit holds.
    private let anchorTree: Set<String>
    /// Files `excluded` leaves out.
    private let excluded: [GlobPattern]

    /// The map of `targets`, for a commit holding `anchorTree`, leaving out
    /// files matching `excluded`.
    init(targets: [TargetSummary], anchorTree: Set<String>, excluded: [String]) {
        entries = targets
            .map { Entry(directory: $0.path, module: $0.name, isTest: $0.isTest) }
            .sorted { ($0.directory.count, $0.directory) > ($1.directory.count, $1.directory) }
        var placements: [String: Entry] = [:]
        for target in targets {
            let entry = Entry(directory: target.path, module: target.name, isTest: target.isTest)
            for file in target.files where placements[file] == nil {
                placements[file] = entry
            }
        }
        compiled = placements
        self.anchorTree = anchorTree
        self.excluded = excluded.map(GlobPattern.init)
    }

    /// The module of the Swift file at `path` and whether it is test code;
    /// nil for a file no target compiles.
    func place(_ path: String) -> Place? {
        guard path.hasSuffix(".swift"), excluded.contains(where: { $0.matches(path) }) == false else {
            return nil
        }
        if let entry = compiled[path] {
            return (entry.module, entry.isTest)
        }
        guard anchorTree.contains(path) == false else {
            return nil
        }
        if let entry = entries.first(where: { $0.directory.isEmpty || path.hasPrefix($0.directory + "/") }) {
            return (entry.module, entry.isTest)
        }
        let parts = path.split(separator: "/")
        guard parts.count >= Self.conventionalPartCount, parts[0] == "Sources" || parts[0] == "Tests" else {
            return nil
        }
        return (String(parts[1]), parts[0] == "Tests")
    }
}
