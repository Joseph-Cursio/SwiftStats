//
//  MutationDropped.swift
//  SwiftStatsCore
//
//  The mutants the mapping leaves out by design (M6, design §3), counted
//  by why; each is still kept, with its class as its reason. None counts
//  against the mapped share.
//

/// How many mutants were dropped, by why.
public struct MutationDropped: Codable, Hashable, Sendable {
    /// The reason a dropped mutant in a `.build` folder carries.
    static let buildReason = "build"
    /// The reason a dropped mutant outside the package root carries.
    static let outsideRootReason = "outsideRoot"
    /// The reason a dropped mutant in a test target's file carries.
    static let testFilesReason = "testFiles"
    /// The reason a dropped mutant in a file that isn't Swift carries.
    static let otherLanguageReason = "otherLanguage"
    /// The reason a dropped mutant in no target's directory carries.
    static let otherPackageReason = "otherPackage"

    /// Under a `.build` folder.
    public let build: Int
    /// Outside the package root.
    public let outsideRoot: Int
    /// In a test target's directory (SwiftMutator's default excludes leave
    /// tests out, so this is a guard).
    public let testFiles: Int
    /// In a file that isn't Swift (a guard).
    public let otherLanguage: Int
    /// In a Swift file under the root but in no target's directory: a
    /// nested package.
    public let otherPackage: Int

    /// Creates the counts. Fields are documented on their properties.
    public init(build: Int, outsideRoot: Int, testFiles: Int, otherLanguage: Int, otherPackage: Int) {
        self.build = build
        self.outsideRoot = outsideRoot
        self.testFiles = testFiles
        self.otherLanguage = otherLanguage
        self.otherPackage = otherPackage
    }

    /// The dropped mutants among `mutants`, counted by their reasons.
    init(_ mutants: [Mutant]) {
        let reasons = mutants.filter { $0.place == .dropped }.map(\.reason)
        self.init(
            build: reasons.count { $0 == Self.buildReason },
            outsideRoot: reasons.count { $0 == Self.outsideRootReason },
            testFiles: reasons.count { $0 == Self.testFilesReason },
            otherLanguage: reasons.count { $0 == Self.otherLanguageReason },
            otherPackage: reasons.count { $0 == Self.otherPackageReason }
        )
    }
}
