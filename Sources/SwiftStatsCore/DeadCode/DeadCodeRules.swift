//
//  DeadCodeRules.swift
//  SwiftStatsCore
//
//  The rules by which an outskirts entry covers records (M7, design
//  §5.4), the first that applies to an unused production entry: `usr` (an
//  id is a record's primary or secondary USR, the index having run);
//  `property` (a variable whose id is a property with accessor records);
//  `type` (a nominal type: the package type its id names with the index,
//  else the innermost type record of a compatible kind holding its
//  position; every function record that type, or a type nested in it,
//  owns, in any file, by the record's primary USR with the index, else by
//  target, type path and file); `extension` (the innermost extension
//  record holding its position: the function records in its range);
//  `location` (a function, the index not having run: the innermost record
//  of a compatible kind holding its name). Anything else covers nothing.
//

/// The rules that map an outskirts entry to records.
struct DeadCodeRules {
    /// The type record kinds each of outskirts' nominal kinds names.
    private static let typeKinds: [String: Set<TypeKind>] = [
        "class": [.actor, .classType],
        "enum": [.enumType],
        "protocol": [.protocolType],
        "struct": [.structType]
    ]
    /// The accessor kinds each of outskirts' accessor kinds names.
    private static let accessorKinds: [String: Set<String>] = [
        "function.accessor.address": ["unsafeAddress"],
        "function.accessor.didset": ["didSet"],
        "function.accessor.getter": ["get"],
        "function.accessor.init": ["init"],
        "function.accessor.modify": ["_modify", "modify"],
        "function.accessor.mutableaddress": ["unsafeMutableAddress"],
        "function.accessor.read": ["_read", "read"],
        "function.accessor.setter": ["set"],
        "function.accessor.willset": ["willSet"]
    ]
    /// The record kind each of outskirts' other function kinds names.
    private static let functionKinds: [String: FunctionKind] = [
        "function.constructor": .initializer,
        "function.destructor": .deinitializer,
        "function.subscript": .subscriptDeclaration
    ]
    /// What a function kind starts with.
    private static let functionPrefix = "function"
    /// What a variable kind starts with.
    private static let variablePrefix = "var."
    /// What an extension kind starts with.
    private static let extensionPrefix = "extension"

    /// The scan.
    let scan: IndexAdapter.Scan
    /// The index facts; nil when the index didn't run.
    let index: DeadCodeIndex?
    /// The function records (top-level code aside), by file.
    private let recordsByFile: [String: [FunctionRecord]]
    /// The records, by key.
    let recordsByKey: [String: FunctionRecord]
    /// The type records' indices, by file.
    private let typesByFile: [String: [Int]]
    /// Each type record's identity, by index.
    private let identities: [TypeIdentity]

    /// The rules over `scan`, with `index` when the index ran.
    init(scan: IndexAdapter.Scan, index: DeadCodeIndex?) {
        self.scan = scan
        self.index = index
        recordsByFile = Dictionary(grouping: scan.records.filter { $0.kind != .topLevelCode }, by: \.file)
        recordsByKey = Dictionary(scan.records.map { ($0.key, $0) }) { first, _ in first }
        typesByFile = Dictionary(grouping: scan.types.indices) { scan.types[$0].file }
        identities = scan.types.map { TypeIdentity($0, fileScopedTypes: scan.fileScopedTypes[$0.file] ?? []) }
    }

    /// Whether `record` is of a kind outskirts' function `kind` can name
    /// (design §3.2, read by outskirts' kinds).
    private static func isCompatible(_ record: FunctionRecord, with kind: String) -> Bool {
        if let accessors = accessorKinds[kind] {
            return record.kind == .accessor && accessors.contains(record.accessorKind ?? "get")
        }
        if let functionKind = functionKinds[kind] {
            return record.kind == functionKind
        }
        return kind.hasPrefix(functionPrefix + ".") && record.kind == .function
    }

    /// What `entry` covers: nothing unless it is an unused production
    /// entry, else by the first rule that applies.
    func cover(of entry: PeripheryEntry) -> DeadCodeCover {
        guard entry.entryClass == .production, entry.hint == DeadCodeMapper.unusedHint, let file = entry.file else {
            return .nothing
        }
        let position = SourcePosition(line: entry.line, column: entry.column)
        if let index, let cover = indexCover(of: entry, index: index) {
            return cover
        }
        if let kinds = Self.typeKinds[entry.kind] {
            return typeCover(of: entry, kinds: kinds, file: file, at: position) ?? .nothing
        }
        if entry.kind.hasPrefix(Self.extensionPrefix) {
            return extensionCover(in: file, at: position) ?? .nothing
        }
        if entry.kind.hasPrefix(Self.functionPrefix), index == nil {
            let holding = recordsByFile[file, default: []].filter { record in
                Self.isCompatible(record, with: entry.kind) && record.range.contains(position)
            }
            if let record = USRJoin.innermost(of: holding, holding: position) {
                return covering([record.key], via: .location)
            }
        }
        return .nothing
    }

    /// What `entry` covers by USR or as a property's accessors with
    /// `index`; nil when neither rule applies.
    private func indexCover(of entry: PeripheryEntry, index: DeadCodeIndex) -> DeadCodeCover? {
        let keys = Set(entry.ids.flatMap { index.recordsByUSR[$0] ?? [] })
        if keys.isEmpty == false {
            return covering(keys, via: .usr)
        }
        guard entry.kind.hasPrefix(Self.variablePrefix) else {
            return nil
        }
        let accessors = Set(entry.ids.flatMap { index.accessorsByProperty[$0] ?? [] })
        return accessors.isEmpty ? nil : covering(accessors, via: .property)
    }

    /// The cover of `keys` by `via`: the records and their lines.
    private func covering(_ keys: some Collection<String>, via: DeadCodeVia) -> DeadCodeCover {
        let sorted = keys.sorted(by: CodePointOrder.precedes)
        return DeadCodeCover(
            via: via,
            keys: sorted,
            unit: nil,
            lines: sorted.compactMap { recordsByKey[$0]?.strippedLines }.reduce(0, +)
        )
    }

    /// What the type entry `entry` of one of `kinds`, at `position` of
    /// `file`, covers; nil when it names no type: with the index, no id is
    /// a package type; without it, no type record of those kinds holds the
    /// position.
    private func typeCover(
        of entry: PeripheryEntry,
        kinds: Set<TypeKind>,
        file: String,
        at position: SourcePosition
    ) -> DeadCodeCover? {
        if let index {
            guard let usr = entry.ids.first(where: { index.typeRecords[$0] != nil }),
                  let record = index.typeRecords[usr] else {
                return nil
            }
            return typeCover(of: record, usr: usr, index: index)
        }
        return innermostType(in: file, at: position, kinds: kinds).map { typeCover(of: $0, usr: nil, index: nil) }
    }

    /// What the type on the type record at `record` covers: every function
    /// record it owns, its lines and its extension records'. With `index`,
    /// the type is `usr`.
    private func typeCover(of record: Int, usr: String?, index: DeadCodeIndex?) -> DeadCodeCover {
        let type = scan.types[record]
        let identity = identities[record]
        let extensions = scan.types.indices.filter { candidate in
            let extensionType = scan.types[candidate]
            guard extensionType.kind == .extensionDeclaration else {
                return false
            }
            if let usr, let index {
                return index.extensionOwners[candidate] == usr
            }
            return extensionType.module == identity.module && extensionType.name == identity.typePath
                && (identity.typeFile.isEmpty || identity.typeFile == extensionType.file)
        }
        .map { scan.types[$0] }
        let keys = recordsByFile.values.flatMap(\.self)
            .filter { owns(identity, usr: usr, index: index, record: $0) }
            .map(\.key)
            .sorted(by: CodePointOrder.precedes)
        return DeadCodeCover(
            via: .type,
            keys: keys,
            unit: .type(type, identity: identity, extensions: extensions),
            lines: ([type] + extensions).map(\.strippedLines).reduce(0, +)
        )
    }

    /// Whether the type `identity` (`usr` with `index`) or a type nested
    /// in it owns `record`: by the record's primary USR with the index,
    /// else (and for a record without a primary USR) by its target, type
    /// path and file.
    private func owns(_ identity: TypeIdentity, usr: String?, index: DeadCodeIndex?, record: FunctionRecord) -> Bool {
        if let usr, let index, index.joined.contains(record.key) {
            guard let owner = index.owners[record.key] else {
                return false
            }
            return owner == usr || (index.identities[owner]?.isNested(in: identity) ?? false)
        }
        guard let typePath = record.typePath else {
            return false
        }
        let owner = TypeIdentity(module: record.module, typePath: typePath, typeFile: record.typeFile ?? "")
        return owner == identity || owner.isNested(in: identity)
    }

    /// What an extension entry at `position` of `file` covers: the
    /// function records in the innermost extension record holding it; nil
    /// when none does.
    private func extensionCover(in file: String, at position: SourcePosition) -> DeadCodeCover? {
        guard let found = innermostType(in: file, at: position, kinds: [.extensionDeclaration]) else {
            return nil
        }
        let type = scan.types[found]
        let keys = recordsByFile[file, default: []].filter { type.range.contains($0.range) }.map(\.key)
        return DeadCodeCover(
            via: .extensionDeclaration,
            keys: keys.sorted(by: CodePointOrder.precedes),
            unit: .extensionRecord(type),
            lines: type.strippedLines
        )
    }

    /// The index of the innermost type record of `file` of one of `kinds`
    /// holding `position`: the one starting last, then ending first, then
    /// first by name.
    private func innermostType(in file: String, at position: SourcePosition, kinds: Set<TypeKind>) -> Int? {
        typesByFile[file, default: []]
            .filter { kinds.contains(scan.types[$0].kind) && scan.types[$0].range.contains(position) }
            .min { lhs, rhs in
                let left = scan.types[lhs]
                let right = scan.types[rhs]
                if left.range.start != right.range.start {
                    return right.range.start < left.range.start
                }
                if left.range.end != right.range.end {
                    return left.range.end < right.range.end
                }
                return CodePointOrder.precedes(left.name, right.name)
            }
    }
}
