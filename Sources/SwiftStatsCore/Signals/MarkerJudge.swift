//
//  MarkerJudge.swift
//  SwiftStatsCore
//
//  Judges risk markers by coverage (PRD §8, M5, risky + untested), taking
//  the first case that applies:
//  1. no coverage data: the marker's function has none, or its line is in
//     an inactive `#if` branch;
//  2. a race marker on a type: untested when none of the type's functions
//     but its initialisers ran anything and one of its functions has
//     coverage data; no function with data, no coverage data. Its
//     attachments neither clear it nor give it data: a type's attachments
//     are summed, so a lazy getter can't be told from a stored-property
//     initialiser, which runs with the initialisers;
//  3. a mapped line: its count, 0 untested, above 0 tested, a partly run
//     line counting as tested; but a marker whose function has data and
//     ran nothing is untested whatever its line says;
//  4. an unmapped line in a function that ran nothing: untested;
//  5. otherwise no coverage data, by reason (a signature in a function that
//     ran, a stored property without an initialiser, a global).
//  It also says which markers lie in production code outside generated
//  files, and what coverage a subject has.
//

/// Judges risk markers against a snapshot's coverage.
struct MarkerJudge {
    /// The production function rows outside generated files.
    private let functions: ProductionFunctions
    /// Each record's coverage, by key.
    private let records: [String: CoverageRecord]
    /// Each file's line data.
    private let lines: CoverageLines
    /// The production rows of each type, by owner.
    private let members: [String: [FunctionRow]]
    /// The coverage attached to each type and file, by target and owner.
    private let attachments: [RiskSubject: [CoverageAttachment]]
    /// The modules with test code: test targets' modules.
    private let testModules: Set<String>
    /// The directories of test targets' functions, each with the
    /// directories above it that hold no production function.
    private let testDirectories: Set<String>
    /// The generated files.
    private let generatedFiles: Set<String>
    /// The files the export holds line data for.
    private let keptFiles: [String]

    /// A judge of `snapshot`'s markers by `coverage`.
    init(_ snapshot: StoredSnapshot, coverage: CoverageReport) {
        functions = ProductionFunctions(snapshot)
        records = Dictionary(coverage.records.map { ($0.key, $0) }) { first, _ in first }
        lines = CoverageLines(coverage)
        let production = snapshot.functions.filter { $0.role == .production }
        members = Dictionary(grouping: production.compactMap { row in
            TypeOwner.of(module: row.module, typePath: row.typePath, typeFile: row.typeFile).map { ($0, row) }
        }, by: \.0).mapValues { $0.map(\.1) }
        attachments = Dictionary(grouping: coverage.attachments) { attachment in
            RiskSubject(target: attachment.attachedTo, name: attachment.owner)
        }
        let tests = snapshot.functions.filter { $0.role != .production }
        testModules = Set(tests.map(\.module))
        testDirectories = Self.testDirectories(tests: tests, production: production)
        generatedFiles = Set(snapshot.functions.filter { $0.facts?.generated == true }.map(\.file))
        keptFiles = coverage.files.map(\.file)
    }

    /// The directory of the file at `path`, relative to the package root;
    /// empty at the root.
    private static func directory(of path: String) -> String {
        guard let slash = path.lastIndex(of: "/") else {
            return ""
        }
        return String(path[..<slash])
    }

    /// The directories of the `tests` rows' files, each with the
    /// directories above it up to the first that holds a `production`
    /// row's file, at any depth: a test target's directory and those above
    /// it, though only its subdirectories hold functions.
    private static func testDirectories(tests: [FunctionRow], production: [FunctionRow]) -> Set<String> {
        var productionDirectories: Set<String> = []
        for row in production {
            var directory = Self.directory(of: row.file)
            while productionDirectories.insert(directory).inserted, directory.isEmpty == false {
                directory = Self.directory(of: directory)
            }
        }
        var directories: Set<String> = []
        for row in tests {
            var directory = Self.directory(of: row.file)
            while productionDirectories.contains(directory) == false, directories.insert(directory).inserted {
                guard directory.isEmpty == false else {
                    break
                }
                directory = Self.directory(of: directory)
            }
        }
        return directories
    }

    /// The sum of `tallies`; nil for none.
    private static func sum(_ tallies: [CoverageTally]) -> CoverageTally? {
        guard tallies.isEmpty == false else {
            return nil
        }
        return CoverageTally(
            covered: tallies.reduce(0) { $0 + $1.covered },
            total: tallies.reduce(0) { $0 + $1.total }
        )
    }

    /// Whether the finding location `row` lies in production code outside
    /// generated files. The store keeps no targets or files, so a type or
    /// a file is production when it is outside the test directories (the
    /// directories of test targets' functions and those above them that
    /// hold no production function), and a type also when its module has
    /// no test code; a file holding no function is taken as not generated.
    /// A test target holding no function at all passes as production.
    func isProduction(_ row: FindingRow) -> Bool {
        guard generatedFiles.contains(row.file) == false else {
            return false
        }
        switch row.attachedTo {
        case .function:
            return row.owner.flatMap(functions.row(key:)) != nil

        case .type:
            let module = row.owner?.components(separatedBy: "::").first
            return module.map { testModules.contains($0) == false } == true && isTestFile(row.file) == false

        case .file:
            return isTestFile(row.file) == false

        case .unscanned:
            return false
        }
    }

    /// The verdict on `marker`, by the first case that applies.
    func verdict(_ marker: RiskMarker) -> MarkerVerdict {
        guard let line = marker.line else {
            return .noData(MarkerVerdict.noLine)
        }
        let record = marker.attachedTo == .function ? marker.owner.flatMap { records[$0] } : nil
        if marker.attachedTo == .function, record?.regions == nil {
            return .noData(MarkerVerdict.functionWithoutData)
        }
        if lines.isSkipped(marker.file, line: line) {
            return .noData(MarkerVerdict.inactive)
        }
        if marker.isRace, marker.attachedTo == .type {
            return typeVerdict(marker.subject)
        }
        let ranNothing = record?.regions.map { $0.covered == 0 } == true
        if let run = lines.run(marker.file, line: line) {
            if ranNothing || run.ran == false {
                return .untested
            }
            return .tested(partlyRun: run.partlyRun)
        }
        if ranNothing {
            return .untested
        }
        if marker.attachedTo == .function {
            return .noData(MarkerVerdict.signature)
        }
        return .noData(lines.holds(marker.file) ? MarkerVerdict.declaration : MarkerVerdict.fileWithoutData)
    }

    /// The coverage of `subject`: a function's own; the sum over a type's
    /// functions with data and its attachments; or what is attached to a file.
    func coverage(of subject: RiskSubject) -> SignalItem.Coverage {
        var lineTallies: [CoverageTally] = []
        var regionTallies: [CoverageTally] = []
        switch subject.target {
        case .function:
            let record = records[subject.name]
            return SignalItem.Coverage(lines: record?.lines, regions: record?.regions)

        case .type:
            for row in members[subject.name] ?? [] {
                if let record = records[row.key], let recordLines = record.lines, let regions = record.regions {
                    lineTallies.append(recordLines)
                    regionTallies.append(regions)
                }
            }

        case .file, .unscanned:
            break
        }
        for attachment in attachments[subject] ?? [] {
            lineTallies.append(attachment.lines)
            regionTallies.append(attachment.regions)
        }
        return SignalItem.Coverage(lines: Self.sum(lineTallies), regions: Self.sum(regionTallies))
    }

    /// The types with coverage data: those with a production function that
    /// has data, outside generated files, or with coverage attached.
    func typesWithData() -> Set<String> {
        var types = Set(attachments.keys.filter { $0.target == .type }.map(\.name))
        for (owner, rows) in members where rows.contains(where: hasData) {
            types.insert(owner)
        }
        return types
    }

    /// The files outside generated ones that the export holds line data for.
    func filesWithData() -> [String] {
        keptFiles.filter { generatedFiles.contains($0) == false }
    }

    /// Whether `row` is production code outside generated files with
    /// coverage data.
    func hasData(_ row: FunctionRow) -> Bool {
        functions.row(key: row.key) != nil && records[row.key]?.regions != nil
    }

    /// Whether the file at `path` lies in a test directory or below one.
    private func isTestFile(_ path: String) -> Bool {
        var directory = Self.directory(of: path)
        while directory.isEmpty == false {
            if testDirectories.contains(directory) {
                return true
            }
            directory = Self.directory(of: directory)
        }
        return testDirectories.contains("")
    }

    /// The verdict on a race marker on the type `subject`, by its
    /// functions alone.
    private func typeVerdict(_ subject: RiskSubject) -> MarkerVerdict {
        let rows = members[subject.name] ?? []
        let withData = rows.filter { records[$0.key]?.regions != nil }
        guard withData.isEmpty == false else {
            return .noData(MarkerVerdict.typeWithoutData)
        }
        let ran = withData.contains { row in
            row.kind != .initializer && (records[row.key]?.regions?.covered ?? 0) > 0
        }
        return ran ? .tested(partlyRun: false) : .untested
    }
}
