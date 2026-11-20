//
//  CloneReport.swift
//  SwiftStatsCore
//
//  What the SwiftCloneDetector collector produced (PRD §7.12): the clone
//  classes of the production files, merged over the tool's passes and
//  attached to records, which files were read, and the tool's own count of
//  duplicated lines per pass, kept as a hint and never trended. Absent
//  when the collector didn't run.
//

/// SwiftCloneDetector's clone classes for one scan.
public struct CloneReport: Codable, Hashable, Sendable {
    /// The tool's `duplicatedLines` for each pass: the first copy's span
    /// once for every further copy, summed over classes, so nested classes
    /// count twice. A hint only.
    public struct DuplicatedLines: Codable, Hashable, Sendable {
        /// The default pass's.
        public let subtree: Int
        /// The `--type1` pass's.
        public let type1: Int
        /// The `--sequence` pass's.
        public let sequence: Int
        /// The `--type3` pass's.
        public let nearMiss: Int

        /// Creates the counts. Fields are documented on their properties.
        public init(subtree: Int, type1: Int, sequence: Int, nearMiss: Int) {
            self.subtree = subtree
            self.type1 = type1
            self.sequence = sequence
            self.nearMiss = nearMiss
        }
    }

    /// The part of the package the tool read: `production`.
    public let part: String
    /// `sha256:<hex>` of the files given to the tool, each path followed by
    /// a newline, in the order given; results depend on the set and order.
    public let fileListHash: String
    /// The tool's own duplicated-line counts.
    public let toolDuplicatedLines: DuplicatedLines
    /// The merged classes, by ordinal.
    public let classes: [CloneClass]

    /// Creates a report. Fields are documented on their properties.
    public init(part: String, fileListHash: String, toolDuplicatedLines: DuplicatedLines, classes: [CloneClass]) {
        self.part = part
        self.fileListHash = fileListHash
        self.toolDuplicatedLines = toolDuplicatedLines
        self.classes = classes
    }
}
