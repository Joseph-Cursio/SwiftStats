//
//  DeadDeclarations.swift
//  SwiftStatsCore
//
//  What outskirts' two runs say of a snapshot's records, for dead but
//  tested (M7, design §5.4, §8.2): each record the `production` run's
//  unused production entries cover, with the entry and the rule (one entry
//  per record, the lower ordinal winning, as the mapping keeps it);
//  whether the `roots` run's entries cover it too; and each of the
//  `production` run's unused production entries as a term of the
//  declarations funnel, the first that applies: a function entry matching
//  a record (it covers one, or an id is a record's primary or secondary
//  USR), a function entry matching none, a nominal type, an extension, a
//  property covering accessor records, else another declaration
//  (parameters, imports, enum cases, stored properties, typealiases).
//

/// outskirts' unused production declarations and the records they cover.
struct DeadDeclarations {
    /// What the declarations funnel counts an unused production entry as.
    enum Term: Hashable {
        /// An extension entry.
        case extensionEntry
        /// A function entry matching a record.
        case matchedFunction
        /// Any other entry: parameters, imports, enum cases, stored
        /// properties, typealiases.
        case other
        /// A property entry covering accessor records.
        case property
        /// A nominal type entry: a class, struct, enum or protocol.
        case typeEntry
        /// A function entry matching no record.
        case unmatchedFunction
    }

    /// The entry covering a record in the `production` run.
    struct Cover {
        /// The entry.
        let declaration: DeadCodeDeclaration
        /// The rule by which it covers the record.
        let via: DeadCodeVia
    }

    /// The terms whose entries' records the declarations funnel's D counts.
    static let coveringTerms: Set<Term> = [.extensionEntry, .matchedFunction, .property, .typeEntry]
    /// outskirts' nominal type kinds.
    private static let typeKinds: Set<String> = ["class", "enum", "protocol", "struct"]
    /// What a function kind starts with.
    private static let functionPrefix = "function."
    /// What a variable kind starts with.
    private static let variablePrefix = "var."
    /// What an extension kind starts with.
    private static let extensionPrefix = "extension"

    /// Each record the `production` run covers, by key.
    private let covers: [String: Cover]
    /// The records the `roots` run covers.
    private let rootsDead: Set<String>
    /// The `production` run's unused production entries' terms, by
    /// ordinal.
    private let terms: [Int: Term]

    /// The `production` run's unused production entries.
    var entries: Int {
        terms.count
    }

    /// The records `report`'s runs cover, with `usrs` the records' primary
    /// and secondary USRs (empty without the index).
    init(_ report: DeadCodeReport, usrs: Set<String>) {
        let unused = report.declarations.filter(\.isUnusedProduction)
        let production = Dictionary(unused.filter { $0.run == .production }.map { ($0.ordinal, $0) }) { first, _ in
            first
        }
        let roots = Set(unused.filter { $0.run == .roots }.map(\.ordinal))
        var covered: [String: Cover] = [:]
        var deadAsRoots: Set<String> = []
        for record in report.records {
            switch record.run {
            case .production:
                if let declaration = production[record.declaration] {
                    covered[record.key] = Cover(declaration: declaration, via: record.via)
                }

            case .roots:
                if roots.contains(record.declaration) {
                    deadAsRoots.insert(record.key)
                }
            }
        }
        let covering = Set(covered.values.map(\.declaration.ordinal))
        covers = covered
        rootsDead = deadAsRoots
        terms = production.mapValues { declaration in
            Self.term(of: declaration, covers: covering.contains(declaration.ordinal), usrs: usrs)
        }
    }

    /// The term of `declaration`, which `covers` records or not, with
    /// `usrs` the records' USRs.
    private static func term(of declaration: DeadCodeDeclaration, covers: Bool, usrs: Set<String>) -> Term {
        let kind = declaration.kind
        if kind.hasPrefix(functionPrefix) {
            return covers || declaration.ids.contains(where: usrs.contains) ? .matchedFunction : .unmatchedFunction
        }
        if typeKinds.contains(kind) {
            return .typeEntry
        }
        if kind.hasPrefix(extensionPrefix) {
            return .extensionEntry
        }
        return kind.hasPrefix(variablePrefix) && covers ? .property : .other
    }

    /// The entry covering the record keyed `key` in the `production` run;
    /// nil when the record isn't production-dead.
    func cover(of key: String) -> Cover? {
        covers[key]
    }

    /// Whether the `roots` run covers the record keyed `key`.
    func isDeadWithTestsAsRoots(_ key: String) -> Bool {
        rootsDead.contains(key)
    }

    /// The `production` run's unused production entries counted as `term`.
    func count(_ term: Term) -> Int {
        terms.values.count { $0 == term }
    }

    /// Of `keys`, the records the entries of the covering terms (function
    /// entries matching a record, types, extensions, properties) cover.
    func coveredByEntries(of keys: Set<String>) -> Int {
        keys.count { key in
            covers[key].flatMap { terms[$0.declaration.ordinal] }.map(Self.coveringTerms.contains) ?? false
        }
    }
}
