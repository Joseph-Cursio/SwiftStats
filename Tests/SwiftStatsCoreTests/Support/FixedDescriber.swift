import Foundation
@testable import SwiftStatsCore

/// A describer that returns the same description for any path, so tests
/// need no SwiftPM.
struct FixedDescriber: PackageDescriber {
    /// The description it returns.
    let package: DescribedPackage

    func describePackage(at _: URL) -> DescribedPackage {
        package
    }
}
