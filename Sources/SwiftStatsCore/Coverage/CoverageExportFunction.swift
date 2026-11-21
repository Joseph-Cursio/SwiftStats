//
//  CoverageExportFunction.swift
//  SwiftStatsCore
//
//  A function entry of llvm-cov's export (M5): every function the compiler
//  instrumented, closures, accessors and property initialisers each their
//  own, with its mangled name, entry count, files and regions, the first
//  of which is its body.
//

/// A function entry of the export.
struct CoverageExportFunction: Decodable, Hashable, Sendable {
    /// The keys read.
    private enum CodingKeys: String, CodingKey {
        case name, count, filenames, regions
    }

    /// The mangled name, unique in the export.
    let name: String
    /// How often it was entered; `Int64.max` when saturated.
    let count: Int64
    /// Its files, the first its own.
    let filenames: [String]
    /// Its regions, sorted by start.
    let regions: [CoverageRegion]

    /// Creates an entry. Fields are documented on their properties.
    init(name: String, count: Int64, filenames: [String], regions: [CoverageRegion]) {
        self.name = name
        self.count = count
        self.filenames = filenames
        self.regions = regions
    }

    /// Decodes an entry, its count as an integer.
    init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        name = try container.decode(String.self, forKey: .name)
        count = try CoverageCount.decode(.count, from: container)
        filenames = try container.decode([String].self, forKey: .filenames)
        regions = try container.decode([CoverageRegion].self, forKey: .regions)
    }
}
