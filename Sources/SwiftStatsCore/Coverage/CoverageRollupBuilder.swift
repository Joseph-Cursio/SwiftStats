//
//  CoverageRollupBuilder.swift
//  SwiftStatsCore
//
//  Sums a coverage report over each production module and the project's
//  production part (M5, §5 of the design). It needs only the targets, the
//  records and the coverage, no declarations, so a fresh scan and a scan
//  that carries earlier coverage build the same roll-ups. Lines come from
//  each kept file's line data, so a line counts once however many records
//  span it; regions from the records' and attachments' regions, which no
//  two of them share; both are null for a scope the export holds nothing
//  of, never 0 of 0. A file belongs to the target that lists it, a record
//  to its module, a type's attachment to the module its owner names.
//

/// Builds the coverage part of a scan's roll-ups.
struct CoverageRollupBuilder {
    /// What one scope counts.
    private struct Scope {
        /// Its records' coverage.
        var records: [CoverageRecord] = []
        /// Its attachments.
        var attachments: [CoverageAttachment] = []
        /// Its kept files' line data.
        var files: [CoverageFileLines] = []
    }

    /// The separator between a type owner's module and its type path.
    private static let moduleSeparator = "::"

    /// The production modules, by name.
    private let modules: Set<String>
    /// Each module's records, attachments and files.
    private let scopes: [String: Scope]
    /// The coverage summed.
    private let coverage: CoverageReport

    /// A builder of `coverage`'s roll-ups over `targets`, whose function
    /// records are `records`.
    init(targets: [TargetSummary], records: [FunctionRecord], coverage: CoverageReport) {
        modules = Set(targets.filter { $0.isTest == false }.map(\.name))
        let fileModules = Dictionary(
            targets.flatMap { target in target.files.map { ($0, target.name) } }
        ) { first, _ in first }
        let recordModules = Dictionary(records.map { ($0.key, $0.module) }) { first, _ in first }
        var byModule: [String: Scope] = [:]
        for record in coverage.records {
            if let module = recordModules[record.key] {
                byModule[module, default: Scope()].records.append(record)
            }
        }
        for attachment in coverage.attachments {
            if let module = Self.module(of: attachment, fileModules: fileModules) {
                byModule[module, default: Scope()].attachments.append(attachment)
            }
        }
        for file in coverage.files {
            if let module = fileModules[file.file] {
                byModule[module, default: Scope()].files.append(file)
            }
        }
        scopes = byModule
        self.coverage = coverage
    }

    /// The module `attachment` belongs to: a type's from its owner, a
    /// file's from the target listing the file.
    private static func module(of attachment: CoverageAttachment, fileModules: [String: String]) -> String? {
        switch attachment.attachedTo {
        case .type:
            attachment.owner.range(of: moduleSeparator).map { String(attachment.owner[..<$0.lowerBound]) }

        case .file, .function, .unscanned:
            fileModules[attachment.owner]
        }
    }

    /// The share of the lines `files` map that ran; nil when there are no
    /// files: the export holds none of the scope's.
    private static func lines(of files: [CoverageFileLines]) -> CoverageRollup.Share? {
        guard files.isEmpty == false else {
            return nil
        }
        let runs = files.flatMap(\.lines)
        return CoverageRollup.Share(
            covered: runs.filter(\.ran).reduce(0) { $0 + $1.length },
            total: runs.reduce(0) { $0 + $1.length }
        )
    }

    /// The share of `tallies` summed.
    private static func sum(_ tallies: [CoverageTally]) -> CoverageRollup.Share {
        CoverageRollup.Share(
            covered: tallies.reduce(0) { $0 + $1.covered },
            total: tallies.reduce(0) { $0 + $1.total }
        )
    }

    /// `records` by coverage data.
    private static func functions(_ records: [CoverageRecord]) -> CoverageRollup.Functions {
        CoverageRollup.Functions(
            withData: records.count { $0.regions != nil },
            executed: records.count { ($0.regions?.covered ?? 0) > 0 },
            noData: records.count { $0.reason != nil }
        )
    }

    /// The public functions among `records`, by how their tests are linked.
    private static func publicFunctions(_ records: [CoverageRecord]) -> CoverageRollup.PublicFunctions {
        let publics = records.filter { $0.link != nil }
        let measured = publics.filter { $0.lines != nil }
        let counts = measured.compactMap(\.linkedTests)
        return CoverageRollup.PublicFunctions(
            total: publics.count,
            withCoverage: measured.count,
            linked: counts.count { $0 > 0 },
            unlinked: counts.count { $0 == 0 },
            reachedGenerically: measured.count { $0.link == .witness },
            extensionMembers: measured.count { $0.link == .extensionMember },
            linkedTests: Distribution(counts)
        )
    }

    /// `rollups` with the coverage of each production module and of the
    /// project's production part; test modules and the `tests` part as
    /// they were.
    func rollups(_ rollups: [Rollup]) -> [Rollup] {
        rollups.map { rollup in
            switch rollup.scope {
            case .module where modules.contains(rollup.name):
                rollup.with(coverage: self.rollup(of: [rollup.name], isProject: false))

            case .project where rollup.name == "production":
                rollup.with(coverage: self.rollup(of: modules, isProject: true))

            case .module, .project:
                rollup
            }
        }
    }

    /// The coverage of `names`' modules; the project's part also counts
    /// the unmapped entries and the attachments.
    func rollup(of names: Set<String>, isProject: Bool) -> CoverageRollup {
        let held = names.sorted().compactMap { scopes[$0] }
        let records = held.flatMap(\.records)
        let attachments = held.flatMap(\.attachments)
        let regions = records.compactMap(\.regions) + attachments.map(\.regions)
        return CoverageRollup(
            lines: Self.lines(of: held.flatMap(\.files)),
            regions: regions.isEmpty ? nil : Self.sum(regions),
            functions: Self.functions(records),
            publicFunctions: Self.publicFunctions(records),
            unmapped: isProject ? coverage.unmapped.count : nil,
            attached: isProject
                ? CoverageRollup.Attached(
                    owners: attachments.count,
                    lines: Self.sum(attachments.map(\.lines)),
                    regions: Self.sum(attachments.map(\.regions))
                )
                : nil
        )
    }
}
