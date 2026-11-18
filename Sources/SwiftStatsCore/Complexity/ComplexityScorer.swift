//
//  ComplexityScorer.swift
//  SwiftStatsCore
//
//  Attaches SwiftCodeMetrics' complexity scores to the function records
//  (PRD §7.3), reusing the scan's parsed trees. The two tools find the same
//  declarations, so a record and its score share a file, a start line and
//  column, and a kind, with one exception: the library also scores
//  functions declared in a macro's arguments, which SwiftStats keeps no
//  record for. Those scores, and any other that joins no record, are
//  reported as warnings rather than dropped (PRD §12).
//

import SwiftCodeMetrics

/// Scores every record with SwiftCodeMetrics.
enum ComplexityScorer {
    /// The UTF-8 byte order mark's length, which SwiftStats counts on line 1.
    private static let byteOrderMarkLength = 3

    /// The SwiftCodeMetrics versions behind the scores.
    static func metricsInfo(ignoresCaseStatements: Bool) -> MetricsInfo {
        let version = SwiftCodeMetrics.version
        return MetricsInfo(
            library: version.library,
            complexityDefinition: version.complexityDefinition,
            swiftLintReference: version.swiftLintReference,
            swiftLintIgnoresCaseStatements: ignoresCaseStatements
        )
    }

    /// `records` with their scores, and a warning for each record the
    /// library gave no score.
    static func score(
        _ records: [FunctionRecord],
        files: [(module: String, file: ParsedFile)],
        ignoresCaseStatements: Bool
    ) -> (records: [FunctionRecord], warnings: [ScanWarning]) {
        var options = MetricsOptions()
        options.complexity.swiftLintIgnoresCaseStatements = ignoresCaseStatements
        var scores: [String: FunctionComplexity] = [:]
        var unjoined: [String: ScanWarning] = [:]
        for (module, file) in files {
            let analysis = SwiftCodeMetrics.functionMetrics(
                of: SourceFileInput(path: file.path, tree: file.tree),
                module: module,
                options: options
            )
            for function in analysis.functions {
                guard let kind = function.kind.swiftStatsKind, let lines = function.lines else {
                    continue
                }
                let isAfterMark = lines.startLine == 1 && file.hasByteOrderMark
                let column = lines.startColumn + (isAfterMark ? byteOrderMarkLength : 0)
                let start = SourcePosition(line: lines.startLine, column: column)
                let key = joinKey(file: file.path, start: start, kind: kind)
                scores[key] = complexity(of: function.complexity)
                let message = "complexity of \(function.name) at line \(lines.startLine) "
                    + "(inside a macro's arguments?) joins no record"
                unjoined[key] = ScanWarning(file: file.path, message: message)
            }
        }
        // A subscript with explicit accessors is scored through them.
        let accessorParents = Set(records.filter { $0.kind == .accessor }.compactMap(\.parentKey))
        var warnings: [ScanWarning] = []
        var joined = Set<String>()
        let scored = records.map { record in
            var copy = record
            let key = joinKey(file: record.file, start: record.range.start, kind: record.kind.rawValue)
            copy.complexity = scores[key]
            joined.insert(key)
            let isScoredThroughAccessors = record.kind == .subscriptDeclaration && accessorParents.contains(record.key)
            if copy.complexity == nil, isScoredThroughAccessors == false {
                warnings.append(ScanWarning(file: record.file, message: "no complexity score for \(record.key)"))
            }
            return copy
        }
        for key in Set(scores.keys).subtracting(joined).sorted() {
            if let warning = unjoined[key] {
                warnings.append(warning)
            }
        }
        return (scored, warnings)
    }

    /// Where a record starts, and what kind it is.
    private static func joinKey(file: String, start: SourcePosition, kind: String) -> String {
        "\(file)|\(start.line)|\(start.column)|\(kind)"
    }

    /// SwiftStats' copy of the library's scores.
    private static func complexity(of scores: ComplexityScores) -> FunctionComplexity {
        let builder: String?
        switch scores.resultBuilderHint {
        case .attribute(let name), .opaqueResult(let name):
            builder = name

        case nil:
            builder = nil
        }
        return FunctionComplexity(
            cognitive: scores.cognitive,
            decisionCount: scores.decisionCount,
            swiftLintCompatible: scores.swiftLintCompatible,
            swiftLintScored: scores.swiftLintScoresKind,
            maxNesting: scores.maxNesting,
            resultBuilder: builder,
            hasSyntaxErrors: scores.hasSyntaxErrors
        )
    }
}
