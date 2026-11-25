//
//  DeadCodeDeclaration.swift
//  SwiftStatsCore
//
//  An entry of an outskirts run as the scan keeps it (M7, design §5.3,
//  §5.4, §9.1's `deadDeclaration`): every entry of both runs, dropped
//  classes included, with its run and 1-based ordinal, the fields outskirts
//  gave (the hint split from its text, modules by target name where they
//  are the package's, the file in the package or none outside the root),
//  its class, where it is listed (the innermost record holding its
//  position, else the innermost type, else its file, as findings attach;
//  `unscanned` for a file the scan didn't parse or that lies outside the
//  root; its file, owning nothing, when the file changed during the scan),
//  its file's module, and the stripped lines it covers: the covered
//  records' for a declaration covering records by USR, accessor or
//  position, its type record's and their extension records' for a type,
//  its extension record's for an extension, none when it covers nothing or
//  isn't an unused production entry.
//

/// One outskirts entry, kept.
public struct DeadCodeDeclaration: Codable, Hashable, Sendable {
    /// The keys the scan JSON writes.
    private enum CodingKeys: String, CodingKey {
        case run
        case ordinal
        case hint
        case hintText
        case kind
        case name
        case accessibility
        case attributes
        case modifiers
        case ids
        case modules
        case entryClass = "class"
        case file
        case line
        case column
        case place
        case owner
        case module
        case strippedLines
    }

    /// The run that reported it.
    public let run: DeadCodeRun
    /// Its 1-based place in that run's output.
    public let ordinal: Int
    /// Its hint's name, such as `unused`.
    public let hint: String
    /// The text in the hint's parentheses; nil when it has none.
    public let hintText: String?
    /// outskirts' kind, such as `function.free` or `var.global`.
    public let kind: String
    /// The declaration's name.
    public let name: String
    /// Its accessibility, as outskirts writes it.
    public let accessibility: String
    /// Its attributes.
    public let attributes: [String]
    /// Its modifiers.
    public let modifiers: [String]
    /// Its ids: USRs, or outskirts' synthetic `param-…` and `import-…` ids.
    public let ids: [String]
    /// Its modules: target names for the package's, else C99 names.
    public let modules: [String]
    /// Its class.
    public let entryClass: PeripheryEntryClass
    /// Its file's path in the package; nil outside the root.
    public let file: String?
    /// The 1-based line of its name.
    public let line: Int
    /// The 1-based UTF-8 column of its name.
    public let column: Int
    /// What it is listed under.
    public let place: FindingTarget
    /// The record's key, or `<module>::<type name>` for a type; nil for a
    /// file or a place outside the scan.
    public let owner: String?
    /// Its file's module; nil when the scan didn't parse the file.
    public let module: String?
    /// The stripped lines it covers; nil when it covers none.
    public let strippedLines: Int?

    /// Whether it is an unused production entry: the entries that are
    /// mapped and make their records dead.
    var isUnusedProduction: Bool {
        entryClass == .production && hint == DeadCodeMapper.unusedHint
    }

    /// Creates a declaration. Fields are documented on their properties.
    public init(
        run: DeadCodeRun,
        ordinal: Int,
        hint: String,
        hintText: String?,
        kind: String,
        name: String,
        accessibility: String,
        attributes: [String],
        modifiers: [String],
        ids: [String],
        modules: [String],
        entryClass: PeripheryEntryClass,
        file: String?,
        line: Int,
        column: Int,
        place: FindingTarget,
        owner: String?,
        module: String?,
        strippedLines: Int?
    ) {
        self.run = run
        self.ordinal = ordinal
        self.hint = hint
        self.hintText = hintText
        self.kind = kind
        self.name = name
        self.accessibility = accessibility
        self.attributes = attributes
        self.modifiers = modifiers
        self.ids = ids
        self.modules = modules
        self.entryClass = entryClass
        self.file = file
        self.line = line
        self.column = column
        self.place = place
        self.owner = owner
        self.module = module
        self.strippedLines = strippedLines
    }

    /// Reads a declaration; it throws for a class no SwiftStats writes.
    public init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let className = try container.decode(String.self, forKey: .entryClass)
        guard let named = PeripheryEntryClass(rawValue: className) else {
            throw DecodingError.dataCorruptedError(
                forKey: .entryClass,
                in: container,
                debugDescription: "no class \(className)"
            )
        }
        try self.init(
            run: container.decode(DeadCodeRun.self, forKey: .run),
            ordinal: container.decode(Int.self, forKey: .ordinal),
            hint: container.decode(String.self, forKey: .hint),
            hintText: container.decodeIfPresent(String.self, forKey: .hintText),
            kind: container.decode(String.self, forKey: .kind),
            name: container.decode(String.self, forKey: .name),
            accessibility: container.decode(String.self, forKey: .accessibility),
            attributes: container.decode([String].self, forKey: .attributes),
            modifiers: container.decode([String].self, forKey: .modifiers),
            ids: container.decode([String].self, forKey: .ids),
            modules: container.decode([String].self, forKey: .modules),
            entryClass: named,
            file: container.decodeIfPresent(String.self, forKey: .file),
            line: container.decode(Int.self, forKey: .line),
            column: container.decode(Int.self, forKey: .column),
            place: container.decode(FindingTarget.self, forKey: .place),
            owner: container.decodeIfPresent(String.self, forKey: .owner),
            module: container.decodeIfPresent(String.self, forKey: .module),
            strippedLines: container.decodeIfPresent(Int.self, forKey: .strippedLines)
        )
    }

    /// Writes the declaration, its class as its raw value and absent
    /// values left out.
    public func encode(to encoder: any Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(run, forKey: .run)
        try container.encode(ordinal, forKey: .ordinal)
        try container.encode(hint, forKey: .hint)
        try container.encodeIfPresent(hintText, forKey: .hintText)
        try container.encode(kind, forKey: .kind)
        try container.encode(name, forKey: .name)
        try container.encode(accessibility, forKey: .accessibility)
        try container.encode(attributes, forKey: .attributes)
        try container.encode(modifiers, forKey: .modifiers)
        try container.encode(ids, forKey: .ids)
        try container.encode(modules, forKey: .modules)
        try container.encode(entryClass.rawValue, forKey: .entryClass)
        try container.encodeIfPresent(file, forKey: .file)
        try container.encode(line, forKey: .line)
        try container.encode(column, forKey: .column)
        try container.encode(place, forKey: .place)
        try container.encodeIfPresent(owner, forKey: .owner)
        try container.encodeIfPresent(module, forKey: .module)
        try container.encodeIfPresent(strippedLines, forKey: .strippedLines)
    }
}
