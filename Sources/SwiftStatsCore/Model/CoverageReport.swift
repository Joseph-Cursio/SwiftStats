//
//  CoverageReport.swift
//  SwiftStatsCore
//
//  What the coverage collector produced (M5, PRD §7.8), mapped onto the
//  scan's records: each production record's lines and regions, coverage
//  attached to types and files, the entries no record takes, the files
//  left out by design, the test bundles and how the tests went, saturated
//  counts, and each kept file's line data. Absent when the collector
//  didn't run.
//

/// The coverage of one scan, mapped to records.
public struct CoverageReport: Codable, Hashable, Sendable {
    /// Each production record's coverage, by key.
    public let records: [CoverageRecord]
    /// Coverage outside every record, by what it attaches to, then owner.
    public let attachments: [CoverageAttachment]
    /// Entries in production targets' files that no record took, by file,
    /// then position, then name.
    public let unmapped: [CoverageUnmapped]
    /// The export's files dropped by design.
    public let dropped: CoverageDropped
    /// The test bundles, each a test target, sorted.
    public let bundles: [String]
    /// `passed`, or `failing` when `swift test` exited non-zero and the
    /// coverage came from the test processes' profiles.
    public let tests: String
    /// Where kept files hold saturated counts, by file, then line.
    public let saturated: [CoverageSaturation]
    /// Each kept file's line data, by path.
    public let files: [CoverageFileLines]

    /// Creates a report. Fields are documented on their properties.
    public init(
        records: [CoverageRecord],
        attachments: [CoverageAttachment],
        unmapped: [CoverageUnmapped],
        dropped: CoverageDropped,
        bundles: [String],
        tests: String,
        saturated: [CoverageSaturation],
        files: [CoverageFileLines]
    ) {
        self.records = records
        self.attachments = attachments
        self.unmapped = unmapped
        self.dropped = dropped
        self.bundles = bundles
        self.tests = tests
        self.saturated = saturated
        self.files = files
    }
}
