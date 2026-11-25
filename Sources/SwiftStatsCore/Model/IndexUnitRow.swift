//
//  IndexUnitRow.swift
//  SwiftStatsCore
//
//  A unit of the T1 build's index store as the scan lists it (M7, design
//  §2.3, §9.1): every unit of the package's files that the filter kept,
//  read as a variant, or set aside as a duplicate, stale or another
//  module's, so the unit set itself can be checked, not only counted.
//

/// One listed unit of the index store.
public struct IndexUnitRow: Codable, Hashable, Sendable {
    /// The keys the scan JSON writes.
    private enum CodingKeys: String, CodingKey {
        case name
        case target
        case mainFile
        case triple
        case unitClass = "class"
    }

    /// The unit's name.
    public let name: String
    /// Its module as a target name; another module's unit keeps its C99
    /// module name.
    public let target: String
    /// Its main file, relative to the package root.
    public let mainFile: String
    /// The target triple it was compiled for.
    public let triple: String
    /// Its class.
    public let unitClass: IndexUnitClass

    /// Creates a row. Fields are documented on their properties.
    public init(name: String, target: String, mainFile: String, triple: String, unitClass: IndexUnitClass) {
        self.name = name
        self.target = target
        self.mainFile = mainFile
        self.triple = triple
        self.unitClass = unitClass
    }

    /// Reads a row; it throws for a class no SwiftStats writes.
    public init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let className = try container.decode(String.self, forKey: .unitClass)
        guard let named = IndexUnitClass(rawValue: className) else {
            throw DecodingError.dataCorruptedError(
                forKey: .unitClass,
                in: container,
                debugDescription: "no class \(className)"
            )
        }
        try self.init(
            name: container.decode(String.self, forKey: .name),
            target: container.decode(String.self, forKey: .target),
            mainFile: container.decode(String.self, forKey: .mainFile),
            triple: container.decode(String.self, forKey: .triple),
            unitClass: named
        )
    }

    /// Writes the row, its class as its raw value.
    public func encode(to encoder: any Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(name, forKey: .name)
        try container.encode(target, forKey: .target)
        try container.encode(mainFile, forKey: .mainFile)
        try container.encode(triple, forKey: .triple)
        try container.encode(unitClass.rawValue, forKey: .unitClass)
    }
}
