import Foundation
@testable import SwiftStatsCore
import Testing

/// The classes of package-relative paths (M5, M6), shared by the coverage
/// and mutation mappings: mutation's paths are relative already, so the
/// classifier itself must tell paths leaving the root.
@Suite("Package file classifier")
struct PackageFileClassifierTests {
    /// A library, a C target and their tests.
    private static let targets = [
        TargetSummary(name: "Lib", type: "library", isTest: false, path: "Sources/Lib", files: []),
        TargetSummary(name: "CFoo", type: "library", isTest: false, path: "Sources/CFoo", files: []),
        TargetSummary(name: "LibTests", type: "test", isTest: true, path: "Tests/LibTests", files: [])
    ]

    @Test("relative paths sort first match wins; an absolute path, or one leaving through .., is outside the root")
    func relativePaths() {
        let classifier = PackageFileClassifier(
            targets: Self.targets,
            parsed: ["Sources/Lib/Lib.swift"],
            excluded: [GlobPattern("Sources/Lib/Gone.swift")]
        )
        let paths = [
            ".build/checkouts/Y/B.swift",
            "../Other/Sources/Lib/Lib.swift",
            "..",
            "/elsewhere/C.swift",
            "Tests/LibTests/T.swift",
            "Tests/LibTests/helper.c",
            "Sources/Lib/Lib.swift",
            "Sources/Lib/Gone.swift",
            "Sources/Lib/Odd.swift",
            "Sources/CFoo/cfoo.c",
            "Sources/LibExtra/E.swift",
            "..hidden/F.swift"
        ]

        #expect(paths.map(classifier.classify) == [
            .build, .outsideRoot, .outsideRoot, .outsideRoot, .testFile, .testFile,
            .kept(path: "Sources/Lib/Lib.swift", module: "Lib"),
            .unmapped(path: "Sources/Lib/Gone.swift", module: "Lib", reason: "excluded"),
            .unmapped(path: "Sources/Lib/Odd.swift", module: "Lib", reason: "not parsed"),
            .otherLanguage, .otherPackage, .otherPackage
        ])
    }
}
