import Foundation
@testable import SwiftStatsCore

/// Describes the package at one root as `HistoryRepository.DiskDescriber`
/// does and fails anywhere else, so a test can tell that a backfill
/// scanned no export.
struct RootOnlyDescriber: PackageDescriber {
    /// The only root it describes.
    let root: URL

    func describePackage(at packageRoot: URL) throws -> DescribedPackage {
        guard packageRoot.standardizedFileURL.path == root.standardizedFileURL.path else {
            throw ScanError.commandFailed("swift package describe", 1, "only \(root.path) is described")
        }
        return HistoryRepository.DiskDescriber().describePackage(at: packageRoot)
    }
}
