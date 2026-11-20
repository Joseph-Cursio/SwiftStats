//
//  CandidateMapper.swift
//  SwiftStatsCore
//
//  Attaches each merged suggestion to the function record it names (PRD
//  §7.11). A location is the line of the `func` keyword, so the finding
//  rules (§7.16) find the function holding it; a computed property is
//  located at its `var`, which can lie outside its getter's range, so it
//  maps to the getter of that name starting on or after the line. A row
//  with no usable location, or one that attaches to a type, a file or a
//  file outside the scan, is kept as unmapped with the reason.
//

/// Attaches suggestions to records.
struct CandidateMapper {
    /// A row's location, when it names a file in the package.
    private struct Place {
        /// The row.
        let row: SwiftInferRow
        /// The file, relative to the package root.
        let file: String
        /// The 1-based line.
        let line: Int
    }

    /// The finding rules over the scan's records, types and files.
    private let findings: FindingMapper
    /// Function records by file.
    private let recordsByFile: [String: [FunctionRecord]]
    /// Types by file.
    private let typesByFile: [String: [TypeRecord]]
    /// Each scanned file by path.
    private let filesByPath: [String: FileRecord]
    /// The test targets' names.
    private let testModules: Set<String>

    /// A mapper over the scan's records, types and files, with each file's
    /// top-level statement lines and the test targets' names.
    init(measured: ScanMeasurements, testModules: Set<String>) {
        findings = FindingMapper(
            records: measured.records,
            types: measured.types,
            files: measured.files,
            topLevelLines: measured.topLevelLines
        )
        recordsByFile = Dictionary(grouping: measured.records, by: \.file)
        typesByFile = Dictionary(grouping: measured.types, by: \.file)
        filesByPath = Dictionary(measured.files.map { ($0.path, $0) }) { first, _ in first }
        self.testModules = testModules
    }

    /// The candidates of `merged`, sorted by file, line, identity, then
    /// population; two locations with no file keep the merge's order.
    func candidates(of merged: MergedCandidates) -> [PropertyCandidate] {
        merged.rows.enumerated()
            .map { (order: $0.offset, candidate: candidate(for: $0.element)) }
            .sorted { lhs, rhs in
                let left = lhs.candidate
                let right = rhs.candidate
                let leftPlace = (left.location?.file ?? "", left.location?.line ?? 0)
                let rightPlace = (right.location?.file ?? "", right.location?.line ?? 0)
                if leftPlace != rightPlace {
                    return leftPlace < rightPlace
                }
                let leftName = (left.identity, left.population.rawValue)
                let rightName = (right.identity, right.population.rawValue)
                return leftName != rightName ? leftName < rightName : lhs.order < rhs.order
            }
            .map(\.candidate)
    }

    /// The candidate of `merged`.
    private func candidate(for merged: MergedCandidates.Row) -> PropertyCandidate {
        let row = merged.row
        let location = place(row).map(attach)
        let primary = location.flatMap { found in
            found.attachedTo == .function ? recordsByFile[found.file]?.first { $0.key == found.owner } : nil
        }
        let partnerKey = primary.flatMap { record in
            row.partner.flatMap { partner(of: record, named: $0) }
        }
        return PropertyCandidate(
            identity: row.identity,
            population: row.population,
            template: row.template,
            tier: row.tier,
            score: row.score,
            blocked: row.blocker != nil,
            function: row.function,
            typeName: row.typeName,
            location: location,
            site: location.flatMap(site(of:)),
            unmapped: location.map(unmapped(_:)) ?? .missingLocation,
            generated: location.flatMap { filesByPath[$0.file]?.generated } ?? false,
            identityCollision: merged.identityCollision,
            partner: row.partner,
            partnerKey: partnerKey
        )
    }

    /// The file and line of `row`'s location, when it names a file in the package.
    private func place(_ row: SwiftInferRow) -> Place? {
        guard let colon = row.location.lastIndex(of: ":"),
              let line = Int(row.location[row.location.index(after: colon)...]) else {
            return nil
        }
        let file = String(row.location[..<colon])
        guard file.isEmpty == false, file.hasPrefix("/") == false, file.hasPrefix("<") == false else {
            return nil
        }
        return Place(row: row, file: file, line: line)
    }

    /// Where `place` attaches: a computed property to its getter, anything
    /// else by the finding rules.
    private func attach(_ place: Place) -> FindingLocation {
        if place.row.isComputedProperty, let getter = getter(of: place) {
            return FindingLocation(
                file: place.file,
                line: place.line,
                column: nil,
                attachedTo: .function,
                owner: getter
            )
        }
        return findings.location(for: RawFinding.Place(file: place.file, line: place.line, column: nil))
    }

    /// The key of the getter of the property `place` names: the getter of
    /// that name, outside any subscript, starting first on or after its line.
    private func getter(of place: Place) -> String? {
        let call = "()"
        let function = place.row.function
        let name = function.hasSuffix(call) ? String(function.dropLast(call.count)) : function
        return (recordsByFile[place.file] ?? [])
            .filter { record in
                record.kind == .accessor && record.accessorKind == "get" && record.parentKey == nil
                    && record.name == name && record.range.start.line >= place.line
            }
            .min { ($0.range.start, $0.key) < ($1.range.start, $1.key) }?
            .key
    }

    /// Why `location` attaches to no function; nil when it does.
    private func unmapped(_ location: FindingLocation) -> PropertyCandidate.Unmapped? {
        switch location.attachedTo {
        case .function:
            return nil

        case .type:
            return .type

        case .file:
            return .file

        case .unscanned:
            return .unscanned
        }
    }

    /// Whether `location` is in a test target's file or a production one;
    /// nil outside the scan.
    private func site(of location: FindingLocation) -> PropertyCandidate.Site? {
        filesByPath[location.file].map { testModules.contains($0.module) ? .test : .production }
    }

    /// The key of the function or getter called `partner`'s base name in
    /// `primary`'s file and innermost type, first in source order.
    private func partner(of primary: FunctionRecord, named partner: String) -> String? {
        let base = partner.split(separator: "(", maxSplits: 1).first.map(String.init) ?? partner
        let records = recordsByFile[primary.file] ?? []
        let owner = innermostType(holding: primary)
        return records
            .filter { record in
                let isFunction = record.kind == .function
                let isGetter = record.kind == .accessor && record.accessorKind == "get" && record.parentKey == nil
                return (isFunction || isGetter) && record.name == base && innermostType(holding: record) == owner
            }
            .min { ($0.range.start, $0.key) < ($1.range.start, $1.key) }?
            .key
    }

    /// The type of the innermost declaration or extension whose range
    /// holds `record`'s start, as `<module>::<name>`, so a type and its
    /// extensions in the file are one type; a local type, which no
    /// extension can name, also by its declaration's start, as
    /// `@<line>:<column>`. nil outside any type.
    private func innermostType(holding record: FunctionRecord) -> String? {
        (typesByFile[record.file] ?? [])
            .filter { $0.range.start <= record.range.start && record.range.start <= $0.range.end }
            .max { $0.range.start < $1.range.start }
            .map { type in
                let identity = "\(type.module)::\(type.name)"
                return type.isLocal ? identity + "@\(type.range.start.line):\(type.range.start.column)" : identity
            }
    }
}
