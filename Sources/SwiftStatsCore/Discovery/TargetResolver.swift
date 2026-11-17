//
//  TargetResolver.swift
//  SwiftStatsCore
//
//  Turns SwiftPM's description of a package into the Swift files each target
//  compiles, with paths relative to the package root. SwiftPM has already
//  chosen the files; this only keeps the Swift ones, joins paths cleanly and
//  orders everything deterministically.
//

/// Maps described targets to scanned targets.
public enum TargetResolver {
    /// One summary per target with Swift sources, sorted by name, each with
    /// its files sorted.
    public static func resolve(_ package: DescribedPackage) -> [TargetSummary] {
        package.targets
            .compactMap { target -> TargetSummary? in
                let directory = normalised(target.path)
                let files = target.sources
                    .filter { $0.hasSuffix(".swift") }
                    .map { normalised(directory.isEmpty ? $0 : directory + "/" + $0) }
                    .sorted()
                guard files.isEmpty == false else {
                    return nil
                }
                return TargetSummary(
                    name: target.name,
                    type: target.type,
                    isTest: target.type == "test",
                    path: directory,
                    files: files
                )
            }
            .sorted { $0.name < $1.name }
    }

    /// `path` with `.` and empty segments removed and `..` applied, so the
    /// package root is "" and no path starts with "./".
    static func normalised(_ path: String) -> String {
        var segments: [Substring] = []
        for segment in path.split(separator: "/", omittingEmptySubsequences: true) {
            switch segment {
            case ".":
                continue

            case "..":
                if segments.isEmpty == false {
                    segments.removeLast()
                }

            default:
                segments.append(segment)
            }
        }
        return segments.joined(separator: "/")
    }
}
