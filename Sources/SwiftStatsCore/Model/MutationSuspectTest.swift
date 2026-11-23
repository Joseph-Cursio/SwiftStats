//
//  MutationSuspectTest.swift
//  SwiftStatsCore
//
//  A test SwiftMutator judged suspect in one run (M6, design §2, §3), from
//  `swift-mutator report -f json`, and why: a failed control run,
//  flakiness when rerun alone, or reach, failing for mutants in too many of
//  the files with kills. SwiftMutator tells tests apart by name and file
//  (`FailedTestLine.TestIdentity`), so two suspect tests may share a name.
//

/// A suspect test of a run.
public struct MutationSuspectTest: Codable, Hashable, Sendable {
    /// The keys the scan JSON writes; the reason is written by name.
    private enum CodingKeys: String, CodingKey {
        case name
        case file
        case run
        case why
        case files
        case filesWithKills
    }

    /// Its name, as SwiftMutator records it.
    public let name: String
    /// The file its issues were recorded in, as SwiftMutator records it (a
    /// file name, such as `SumTests.swift`), which with the name tells it
    /// apart; none for an XCTest test, whose failures give no location.
    public let file: String?
    /// The ordinal of the run that judged it.
    public let run: Int
    /// Why it is suspect.
    public let why: SuspectReason
    /// For `reach`: how many files with kills it failed in.
    public let files: Int?
    /// For `reach`: how many files have a kill naming a test.
    public let filesWithKills: Int?

    /// Creates a suspect test. Fields are documented on their properties.
    public init(name: String, file: String?, run: Int, why: SuspectReason, files: Int?, filesWithKills: Int?) {
        self.name = name
        self.file = file
        self.run = run
        self.why = why
        self.files = files
        self.filesWithKills = filesWithKills
    }

    /// Reads a suspect test; it throws for a reason no SwiftStats writes.
    public init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let reason = try container.decode(String.self, forKey: .why)
        guard let named = SuspectReason(rawValue: reason) else {
            throw DecodingError.dataCorruptedError(forKey: .why, in: container, debugDescription: "no reason \(reason)")
        }
        try self.init(
            name: container.decode(String.self, forKey: .name),
            file: container.decodeIfPresent(String.self, forKey: .file),
            run: container.decode(Int.self, forKey: .run),
            why: named,
            files: container.decodeIfPresent(Int.self, forKey: .files),
            filesWithKills: container.decodeIfPresent(Int.self, forKey: .filesWithKills)
        )
    }

    /// Whether `lhs` comes before `rhs` in a report: by run, then name,
    /// then file, a test with none first, as SwiftMutator orders them.
    static func reportOrder(_ lhs: Self, _ rhs: Self) -> Bool {
        if (lhs.run, lhs.name) != (rhs.run, rhs.name) {
            return (lhs.run, lhs.name) < (rhs.run, rhs.name)
        }
        switch (lhs.file, rhs.file) {
        case let (left?, right?):
            return left < right

        case (nil, .some):
            return true

        case (.some, nil), (nil, nil):
            return false
        }
    }

    /// Writes the suspect test, leaving out the file and counts it doesn't
    /// have.
    public func encode(to encoder: any Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(name, forKey: .name)
        try container.encodeIfPresent(file, forKey: .file)
        try container.encode(run, forKey: .run)
        try container.encode(why.rawValue, forKey: .why)
        try container.encodeIfPresent(files, forKey: .files)
        try container.encodeIfPresent(filesWithKills, forKey: .filesWithKills)
    }
}
