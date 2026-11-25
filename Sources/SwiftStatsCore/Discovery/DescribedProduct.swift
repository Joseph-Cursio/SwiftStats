//
//  DescribedProduct.swift
//  SwiftStatsCore
//
//  One product from `swift package describe --type json` (M7, design §1.3):
//  its name, its kind and the targets it holds. The T1 group reads which
//  targets library products list (outskirts' `--retain-public-modules`,
//  test-only production code's public-API exclusion).
//

/// A product as SwiftPM describes it.
public struct DescribedProduct: Decodable, Hashable, Sendable {
    private enum CodingKeys: String, CodingKey {
        case name, targets, type
    }

    /// A key of the `type` object, whatever SwiftPM names it.
    private struct KindKey: CodingKey {
        /// The key as written.
        let stringValue: String

        /// No integer form: `type`'s keys are names.
        var intValue: Int? {
            nil
        }

        /// The key `stringValue`.
        init(stringValue: String) {
            self.stringValue = stringValue
        }

        /// No key from an integer.
        init?(intValue _: Int) {
            nil
        }
    }

    /// The product name.
    public let name: String
    /// The product kind: the key SwiftPM writes its `type` under
    /// (`library`, `executable`, `macro`, `plugin`, `snippet`, `test`); a
    /// library's linkage is not kept.
    public let kind: String
    /// The package's targets the product holds, by name.
    public let targets: [String]

    /// Creates a product. Fields are documented on their properties.
    public init(name: String, kind: String, targets: [String]) {
        self.name = name
        self.kind = kind
        self.targets = targets
    }

    /// Decodes SwiftPM's form, whose `type` is an object with one key
    /// (`{"library": ["automatic"]}`, `{"executable": null}`); a plain
    /// string is read as the kind, and an object with several keys gives
    /// the first in byte order.
    public init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        name = try container.decode(String.self, forKey: .name)
        targets = try container.decodeIfPresent([String].self, forKey: .targets) ?? []
        if let written = try? container.decode(String.self, forKey: .type) {
            kind = written
        } else {
            let type = try container.nestedContainer(keyedBy: KindKey.self, forKey: .type)
            kind = type.allKeys.map(\.stringValue).min() ?? ""
        }
    }
}
