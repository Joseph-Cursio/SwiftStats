import Foundation
@testable import SwiftStatsCore

/// Describes a package as `HistoryRepository.DiskDescriber` does, but fails
/// as swiftly does when the nearest `.swift-version` at or above the package
/// names a toolchain that isn't installed, so a test needs neither swiftly
/// nor an old toolchain.
struct PinRefusingDescriber: PackageDescriber {
    /// The toolchain version no install has.
    static let uninstalled = "0.0.1"

    /// The pin swiftly reads.
    private static let pinName = ".swift-version"

    /// The contents of the nearest pin at or above `packageRoot`, or nil.
    private static func nearestPin(above packageRoot: URL) -> String? {
        var directory = packageRoot.standardizedFileURL
        while true {
            let pin = directory.appendingPathComponent(pinName)
            if let contents = try? String(contentsOf: pin, encoding: .utf8) {
                return contents.trimmingCharacters(in: .whitespacesAndNewlines)
            }
            guard directory.pathComponents.count > 1 else {
                return nil
            }
            directory = directory.deletingLastPathComponent()
        }
    }

    func describePackage(at packageRoot: URL) throws -> DescribedPackage {
        if let pin = Self.nearestPin(above: packageRoot), pin == Self.uninstalled {
            throw ScanError.commandFailed(
                "swift package describe",
                1,
                "The swift version file uses toolchain version \(pin), which isn't installed"
            )
        }
        return HistoryRepository.DiskDescriber().describePackage(at: packageRoot)
    }
}
