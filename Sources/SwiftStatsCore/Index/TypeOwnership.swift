//
//  TypeOwnership.swift
//  SwiftStatsCore
//
//  The package's types in the T1 build's index and what owns each
//  declaration (M7, design §4.3). A type is a struct, class (actors
//  included), enum or protocol whose explicit definition lies in a scanned
//  file that didn't change, named by its USR and placed on the innermost
//  type record holding the definition when that record's kind matches; a
//  type in a test target isn't a production type. An extension is placed
//  on the innermost extension record holding its definition. A
//  declaration's owning type: a package type owns itself; an extension is
//  owned by the package type its head names (`extendedBy`), and by none
//  when it extends a type the package doesn't declare; anything else
//  follows its definition's `childOf` chain to the first of those, so a
//  nested type's members belong to the nested type and an extension's
//  members to the extended type. A definition no type record of a
//  matching kind holds (a type inside a macro's closure, which the scan
//  doesn't measure) is kept apart, for the index collector's warning.
//

/// The package's types and the owners of declarations.
struct TypeOwnership {
    /// A package type.
    struct PackageType {
        /// Its USR.
        let usr: String
        /// Its identity, from its type record.
        let identity: TypeIdentity
        /// The index of its type record in the scan's type records.
        let record: Int
        /// Its target.
        let module: String
        /// Whether its target isn't a test target.
        let isProduction: Bool
    }

    /// The rule, as the `index` collector's `types:` option states it.
    static let rule = "package-declared nominal types by USR; an extension's members belong to the package type its "
        + "head extends, none for an external type; fan-in by distinct referring types or free functions per target; "
        + "cycles over production types without type-to-nested-type edges"

    /// Each index kind a type record's kind matches (actors are classes in
    /// the index).
    private static let indexKinds: [TypeKind: Int] = [
        .actor: IndexSymbolKind.class,
        .classType: IndexSymbolKind.class,
        .enumType: IndexSymbolKind.enum,
        .protocolType: IndexSymbolKind.protocol,
        .structType: IndexSymbolKind.struct
    ]

    /// The package types, by USR.
    let types: [String: PackageType]
    /// The scan's type records.
    let records: [TypeRecord]
    /// The type definitions that found no type record of a matching kind,
    /// in definition order (by file, position, USR, then kind).
    let unplaced: [OccurrenceFacts.Located]
    /// Each type record's identity, by index.
    private let identities: [TypeIdentity]
    /// The type records of each file, by index.
    private let recordsByFile: [String: [Int]]
    /// The package type placed on each type record, by index.
    private let typeOfRecord: [Int: String]
    /// The extension placed on each extension record, by index.
    private let extensionOfRecord: [Int: String]
    /// Each declaration's owning type, by USR; absent when it has none.
    private let owners: [String: String]

    /// The types and owners `facts` give, placed on `records` (the scan's
    /// type records, each file's file-scoped types in `fileScopedTypes`),
    /// a type in one of `testModules` not a production type; extensions
    /// placed only in `joinable` files (scanned, unchanged).
    init(
        facts: OccurrenceFacts,
        records: [TypeRecord],
        fileScopedTypes: [String: Set<String>],
        testModules: Set<String>,
        joinable: Set<String>
    ) {
        self.records = records
        identities = records.map { TypeIdentity($0, fileScopedTypes: fileScopedTypes[$0.file] ?? []) }
        recordsByFile = Dictionary(grouping: records.indices) { records[$0].file }
        var placed: [String: PackageType] = [:]
        var typeRecords: [Int: String] = [:]
        var missed: [OccurrenceFacts.Located] = []
        for located in facts.typeDefinitions.sorted(by: Self.definitionOrder) {
            let occurrence = located.occurrence
            guard placed[occurrence.usr] == nil else {
                continue
            }
            let position = SourcePosition(line: occurrence.line, column: occurrence.column)
            guard let index = Self.innermost(in: located.file, at: position, records: records, byFile: recordsByFile),
                  Self.indexKinds[records[index].kind] == occurrence.kind else {
                missed.append(located)
                continue
            }
            placed[occurrence.usr] = PackageType(
                usr: occurrence.usr,
                identity: identities[index],
                record: index,
                module: records[index].module,
                isProduction: testModules.contains(records[index].module) == false
            )
            if typeRecords[index] == nil {
                typeRecords[index] = occurrence.usr
            }
        }
        types = placed
        typeOfRecord = typeRecords
        unplaced = missed
        extensionOfRecord = Self.extensions(facts, records: records, byFile: recordsByFile, joinable: joinable)
        owners = Self.owners(facts, types: placed)
    }

    /// Whether `lhs` comes before `rhs`: by file, position, USR, then kind.
    private static func definitionOrder(_ lhs: OccurrenceFacts.Located, _ rhs: OccurrenceFacts.Located) -> Bool {
        let left = lhs.occurrence
        let right = rhs.occurrence
        if lhs.file != rhs.file {
            return CodePointOrder.precedes(lhs.file, rhs.file)
        }
        if (left.line, left.column) != (right.line, right.column) {
            return (left.line, left.column) < (right.line, right.column)
        }
        if left.usr != right.usr {
            return CodePointOrder.precedes(left.usr, right.usr)
        }
        return left.kind < right.kind
    }

    /// The innermost of `records` in `file` (indices `byFile`) holding
    /// `position`, of `kind` when given: the one starting last, then
    /// ending first, then first by type path.
    private static func innermost(
        in file: String,
        at position: SourcePosition,
        records: [TypeRecord],
        byFile: [String: [Int]],
        kind: TypeKind? = nil
    ) -> Int? {
        byFile[file, default: []]
            .filter { records[$0].range.contains(position) && (kind == nil || records[$0].kind == kind) }
            .min { lhs, rhs in
                let left = records[lhs]
                let right = records[rhs]
                if left.range.start != right.range.start {
                    return right.range.start < left.range.start
                }
                if left.range.end != right.range.end {
                    return left.range.end < right.range.end
                }
                return CodePointOrder.precedes(left.name, right.name)
            }
    }

    /// The extension placed on each extension record of `records` (indices
    /// by file `byFile`): extensions taken by USR, each on the innermost
    /// extension record holding its definition in a `joinable` file, the
    /// first by USR keeping a record.
    private static func extensions(
        _ facts: OccurrenceFacts,
        records: [TypeRecord],
        byFile: [String: [Int]],
        joinable: Set<String>
    ) -> [Int: String] {
        var placed: [Int: String] = [:]
        for (usr, located) in facts.extensionDefinitions.sorted(by: { CodePointOrder.precedes($0.key, $1.key) })
        where joinable.contains(located.file) {
            let position = SourcePosition(line: located.occurrence.line, column: located.occurrence.column)
            if let index = innermost(
                in: located.file,
                at: position,
                records: records,
                byFile: byFile,
                kind: .extensionDeclaration
            ), placed[index] == nil {
                placed[index] = usr
            }
        }
        return placed
    }

    /// Each declaration's owning type among `types`, by USR, for every USR
    /// `facts` gives a parent, every type and every extension.
    private static func owners(_ facts: OccurrenceFacts, types: [String: PackageType]) -> [String: String] {
        var symbols = Set(facts.childOf.keys)
        symbols.formUnion(types.keys)
        symbols.formUnion(facts.extensionDefinitions.keys)
        var found: [String: String] = [:]
        for usr in symbols {
            var current: String? = usr
            var walked: Set<String> = []
            while let symbol = current, walked.insert(symbol).inserted {
                if types[symbol] != nil {
                    found[usr] = symbol
                    break
                }
                if facts.extensionDefinitions[symbol] != nil {
                    if let head = facts.extended[symbol], types[head] != nil {
                        found[usr] = head
                    }
                    break
                }
                current = facts.childOf[symbol]?.usr
            }
        }
        return found
    }

    /// The owning package type of the declaration `usr`; nil when it has
    /// none.
    func owner(of usr: String) -> String? {
        owners[usr]
    }

    /// The owning package type of the type record at `index`: the type
    /// placed on it, or for an extension record its extension's owner.
    func owner(ofRecord index: Int) -> String? {
        if records[index].kind == .extensionDeclaration {
            return extensionOfRecord[index].flatMap(owner(of:))
        }
        return typeOfRecord[index]
    }

    /// The identity of the type record at `index`.
    func identity(ofRecord index: Int) -> TypeIdentity {
        identities[index]
    }

    /// The innermost type record of `file` holding `position`, of any kind.
    func innermostRecord(in file: String, at position: SourcePosition) -> Int? {
        Self.innermost(in: file, at: position, records: records, byFile: recordsByFile)
    }

    /// Whether one of the package types `first` and `second` is nested in
    /// the other, as `TypeIdentity.isNested(in:)` says: a `private` type
    /// nested in a plain one counts, though only the inner one is
    /// file-scoped.
    func isNested(_ first: String, _ second: String) -> Bool {
        guard let lhs = types[first]?.identity, let rhs = types[second]?.identity else {
            return false
        }
        return lhs.isNested(in: rhs) || rhs.isNested(in: lhs)
    }
}
