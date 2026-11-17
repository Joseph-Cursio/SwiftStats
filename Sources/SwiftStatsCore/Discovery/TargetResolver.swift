//
//  TargetResolver.swift
//  SwiftStatsCore
//
//  Turns manifest targets into the Swift files each one compiles, following
//  SwiftPM's layout rules: a custom `path` or the default source directory,
//  an explicit `sources` list, `exclude`, hidden files skipped, and files of a
//  target nested inside another target's directory left to the nested one.
//

import Foundation

/// Resolves which Swift files belong to which target.
public struct TargetResolver {
    /// Target types that contain no Swift source to scan.
    private static let sourcelessTypes: Set<String> = ["binary", "system"]

    /// Default parent directories SwiftPM searches for non-test targets.
    private static let sourceDirectories = ["Sources", "Source", "src", "srcs"]

    /// The file manager used to walk directories.
    private let fileManager: FileManager

    /// Creates a resolver that reads the file system through `fileManager`.
    public init(fileManager: FileManager = .default) {
        self.fileManager = fileManager
    }

    /// `path` without a leading `./` or trailing `/`.
    private static func normalised(_ path: String) -> String {
        var result = path
        while result.hasPrefix("./") {
            result.removeFirst("./".count)
        }
        while result.hasSuffix("/") {
            result.removeLast()
        }
        return result
    }

    /// Returns one summary per scannable target, in manifest order, with
    /// paths relative to `packageRoot` and files sorted.
    public func resolve(_ manifest: PackageManifest, packageRoot: URL) -> [TargetSummary] {
        let root = packageRoot.standardizedFileURL
        let located: [(target: ManifestTarget, directory: String)] = manifest.targets.compactMap { target in
            guard Self.sourcelessTypes.contains(target.type) == false,
                  let directory = directory(for: target, root: root) else {
                return nil
            }
            return (target, directory)
        }
        let allDirectories = located.map(\.directory)

        return located.map { entry in
            let nestedDirectories = allDirectories.filter { other in
                other != entry.directory && other.hasPrefix(entry.directory + "/")
            }
            let files = swiftFiles(for: entry.target, directory: entry.directory, root: root)
                .filter { file in
                    nestedDirectories.contains { file.hasPrefix($0 + "/") } == false
                }
            return TargetSummary(
                name: entry.target.name,
                type: entry.target.type,
                isTest: entry.target.type == "test",
                path: entry.directory,
                files: files
            )
        }
    }

    /// The target's source directory relative to the root, or nil if it
    /// doesn't exist.
    private func directory(for target: ManifestTarget, root: URL) -> String? {
        if let path = target.path {
            let trimmed = Self.normalised(path)
            return isDirectory(root.appendingPathComponent(trimmed)) ? trimmed : nil
        }
        let parents: [String]
        switch target.type {
        case "test":
            parents = ["Tests"]

        case "plugin":
            parents = ["Plugins"]

        default:
            parents = Self.sourceDirectories
        }
        return parents
            .map { "\($0)/\(target.name)" }
            .first { isDirectory(root.appendingPathComponent($0)) }
    }

    /// Sorted Swift files of the target, relative to the package root.
    private func swiftFiles(for target: ManifestTarget, directory: String, root: URL) -> [String] {
        let excluded = target.exclude.map { "\(directory)/\(Self.normalised($0))" }
        let starts = (target.sources.isEmpty ? [""] : target.sources).map { source in
            source.isEmpty ? directory : "\(directory)/\(Self.normalised(source))"
        }
        var files = Set<String>()
        for start in starts {
            files.formUnion(walk(start, root: root))
        }
        return files
            .filter { file in
                excluded.contains { file == $0 || file.hasPrefix($0 + "/") } == false
            }
            .sorted()
    }

    /// Swift files at or under `relativePath`, skipping hidden entries.
    private func walk(_ relativePath: String, root: URL) -> [String] {
        let url = root.appendingPathComponent(relativePath)
        guard isDirectory(url) else {
            return relativePath.hasSuffix(".swift") && fileManager.fileExists(atPath: url.path)
                ? [relativePath]
                : []
        }
        // The path-based enumerator yields paths relative to `url`, which keeps
        // results independent of symlinks such as /tmp → /private/tmp.
        guard let enumerator = fileManager.enumerator(atPath: url.path) else {
            return []
        }
        var found = [String]()
        while let item = enumerator.nextObject() as? String {
            let name = item.split(separator: "/").last.map(String.init) ?? item
            if name.hasPrefix(".") {
                enumerator.skipDescendants()
                continue
            }
            guard item.hasSuffix(".swift"), isDirectory(url.appendingPathComponent(item)) == false else {
                continue
            }
            found.append("\(relativePath)/\(item)")
        }
        return found
    }

    /// Whether `url` names an existing directory.
    private func isDirectory(_ url: URL) -> Bool {
        var isDirectory: ObjCBool = false
        return fileManager.fileExists(atPath: url.path, isDirectory: &isDirectory) && isDirectory.boolValue
    }
}
