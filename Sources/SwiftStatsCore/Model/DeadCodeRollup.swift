//
//  DeadCodeRollup.swift
//  SwiftStatsCore
//
//  Dead code over a production module or the production part (M7, design
//  §5.4, §10.1, §10.3): the records dead with tests as roots and the
//  production-dead records, the `roots` run's unused production
//  declarations by kind, and those of them with no line count. The line
//  ratio's dead lines are in `tests.lineRatio.deadLines`.
//

/// Dead-code counts over one scope.
public struct DeadCodeRollup: Codable, Hashable, Sendable {
    /// The kinds unused declarations are counted by, in order.
    static let kinds = ["function", "type", "extension", "property", "enumCase", "parameter", "import", "other"]
    /// What a function kind starts with.
    private static let functionPrefix = "function"
    /// What an extension kind starts with.
    private static let extensionPrefix = "extension"
    /// What a variable kind starts with.
    private static let variablePrefix = "var."
    /// outskirts' nominal type kinds.
    private static let typeKinds: Set = ["class", "enum", "protocol", "struct"]
    /// The kind each outskirts kind outside the prefixes is counted as.
    private static let exactKinds = ["enumelement": "enumCase", "module": "import", "var.parameter": "parameter"]

    /// Records the `roots` run covers: dead with tests as roots.
    public let records: Int
    /// Records the `production` run covers: production-dead.
    public let productionRecords: Int
    /// The `roots` run's unused production declarations with no line
    /// count: properties without accessors, enum cases, parameters,
    /// imports, and declarations covering nothing.
    public let unsized: Int
    /// The `roots` run's unused production declarations by kind
    /// (`function`, `type`, `extension`, `property`, `enumCase`,
    /// `parameter`, `import`, `other`), every kind listed.
    public let unused: [String: Int]

    /// Creates the counts. Fields are documented on their properties.
    public init(records: Int, productionRecords: Int, unsized: Int, unused: [String: Int]) {
        self.records = records
        self.productionRecords = productionRecords
        self.unsized = unsized
        self.unused = unused
    }

    /// The counts of `records` and `productionRecords`, each run's covered
    /// records, and of `declarations`, the `roots` run's unused production
    /// declarations.
    init(records: Int, productionRecords: Int, declarations: [DeadCodeDeclaration]) {
        var counts = Dictionary(uniqueKeysWithValues: Self.kinds.map { ($0, 0) })
        for declaration in declarations {
            counts[Self.kind(of: declaration.kind), default: 0] += 1
        }
        self.init(
            records: records,
            productionRecords: productionRecords,
            unsized: declarations.count { $0.strippedLines == nil },
            unused: counts
        )
    }

    /// The kind outskirts' `kind` is counted as (design §10.1).
    static func kind(of kind: String) -> String {
        if let exact = exactKinds[kind] {
            return exact
        }
        if kind.hasPrefix(functionPrefix) {
            return "function"
        }
        if typeKinds.contains(kind) {
            return "type"
        }
        if kind.hasPrefix(extensionPrefix) {
            return "extension"
        }
        return kind.hasPrefix(variablePrefix) ? "property" : "other"
    }
}
