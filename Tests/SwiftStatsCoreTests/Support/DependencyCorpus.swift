import Foundation

/// The packages the parity test reads.
enum DependencyCorpus {
    /// swift-algorithms and SwiftCodeMetrics on this machine. Not this
    /// package: `swift test` holds its `.build` lock, so SwiftPM commands run
    /// in it from a test wait forever.
    static let packages = [
        "GitHub_projects/swift-algorithms", "xcode_projects/SwiftCodeMetrics"
    ].map { FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent($0) }

    /// Whether every package exists with its dependencies resolved.
    static let isAvailable = packages.allSatisfy(isResolved)

    /// Whether `root` is a package whose dependencies are resolved.
    static func isResolved(_ root: URL) -> Bool {
        FileManager.default.fileExists(atPath: root.appendingPathComponent(".build/workspace-state.json").path)
    }
}
