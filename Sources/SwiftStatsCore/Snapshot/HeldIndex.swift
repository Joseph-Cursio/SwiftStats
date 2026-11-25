//
//  HeldIndex.swift
//  SwiftStatsCore
//
//  The T1 results a stored snapshot holds, as a rescan whose build didn't
//  run needs them to decide whether to carry them (M7, design §9.4): where
//  the snapshot stood in git, its `build`, `index` and `periphery` runs,
//  the three blocks read back from their rows (never the report blob), the
//  `swiftc` findings and the warnings describing the results, and what the
//  carry is checked against: every record of every role with its full
//  span, family and owning type, every type record with its span, and
//  every scanned file's SHA-256. The store's `function` rows keep no
//  columns, so the records, types, files and findings come from the
//  stored report, decoded only as far as they go.
//

/// A stored snapshot's T1 results and what carrying them is checked
/// against.
struct HeldIndex {
    /// Where a stored record was, and what it belonged to.
    struct Place: Hashable {
        /// Its file, relative to the package root.
        let file: String
        /// Its full span, columns included.
        let range: SourceSpan
        /// Its family's id (`FunctionFamily.id`): its root's key, or a
        /// computed property's key without its accessor part.
        let family: String
        /// The type that owns it, when one does.
        let typePath: String?
        /// The file a file-scoped owning type is declared in.
        let typeFile: String?
    }

    /// A stored type record: what names it and where it was.
    struct TypeSpan: Hashable, Comparable {
        /// Its module.
        let module: String
        /// Its name, with its enclosing types'.
        let name: String
        /// Its file, relative to the package root.
        let file: String
        /// Its full span, columns included.
        let range: SourceSpan

        /// `record` as the carry compares it.
        init(_ record: TypeRecord) {
            module = record.module
            name = record.name
            file = record.file
            range = record.range
        }

        /// Types by file, then name, then start and end, then module.
        static func < (lhs: Self, rhs: Self) -> Bool {
            if lhs.file != rhs.file {
                return lhs.file < rhs.file
            }
            if lhs.name != rhs.name {
                return lhs.name < rhs.name
            }
            if lhs.range.start != rhs.range.start {
                return lhs.range.start < rhs.range.start
            }
            if lhs.range.end != rhs.range.end {
                return lhs.range.end < rhs.range.end
            }
            return lhs.module < rhs.module
        }
    }

    /// Where the snapshot stood in git.
    let git: GitState
    /// Its `build` run, which ran.
    let build: CollectorRunInfo
    /// Its `index` and `periphery` runs, in that order, as they ended.
    let readers: [CollectorRunInfo]
    /// When the T1 build ran.
    let collectedAt: String
    /// The build results.
    let buildReport: BuildReport
    /// The index results; nil when the `index` collector didn't run.
    let index: IndexReport?
    /// The dead-code results; nil when the `periphery` collector didn't
    /// run.
    let deadCode: DeadCodeReport?
    /// The build's warnings, as the snapshot's `swiftc` findings.
    let findings: [Finding]
    /// The warnings the T1 collectors gave describing their results
    /// (`IndexCarry.describesResults`), in the stored report's order.
    let warnings: [ScanWarning]
    /// Where each of the snapshot's records was, of every role, by key.
    let records: [String: Place]
    /// The snapshot's type records.
    let types: [TypeSpan]
    /// Each scanned file's SHA-256, by path: the index's hashes, taken
    /// after the build, or, when the index didn't run, the scan's; nil
    /// when the file could no longer be read after the build.
    let files: [String: String?]

    /// The three runs, `build`, `index` and `periphery`.
    var runs: [CollectorRunInfo] {
        [build] + readers
    }

    /// Where each of `records` is, by key, as the carry compares them;
    /// the first of a key wins.
    static func places(of records: [FunctionRecord]) -> [String: Place] {
        var families: [String: String] = [:]
        for family in FunctionFamily.families(records.map { FunctionRow($0, snapshotId: 0) }) {
            for member in family.members where families[member.key] == nil {
                families[member.key] = family.id
            }
        }
        let places = records.map { record in
            (
                record.key,
                Place(
                    file: record.file,
                    range: record.range,
                    family: families[record.key] ?? record.key,
                    typePath: record.typePath,
                    typeFile: record.typeFile
                )
            )
        }
        return Dictionary(places) { first, _ in first }
    }
}
