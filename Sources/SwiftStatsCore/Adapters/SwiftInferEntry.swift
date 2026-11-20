//
//  SwiftInferEntry.swift
//  SwiftStatsCore
//
//  One row of a `swift-infer` index, from either list (PRD §7.11): the
//  fields SwiftStats reads, and the stable ones whole, so two targets'
//  rows can be compared. Timestamps and the location, which names the
//  directory the tool ran in, are left out of the comparison.
//

import Foundation

/// A row of either list: the fields SwiftStats reads, and the rest as written.
struct SwiftInferEntry: Decodable {
    private enum CodingKeys: String, CodingKey {
        case family, identityHash, isComputedProperty, location, primaryFunctionName, qualifiedTypeName
        case reducerQualifiedName, score, secondaryFunctionName, structuralBlocker, templateName, tier
        case typeName, typeShape
    }

    /// The keys whose values change with every run, or name the run's directory.
    private static let unstableKeys: Set<String> = ["decisionAt", "firstSeenAt", "lastSeenAt", "location"]

    /// The identity hash.
    let identityHash: String
    /// The template; nil on interaction rows.
    let templateName: String?
    /// The family; nil on algebraic rows.
    let family: String?
    /// The score.
    let score: Int
    /// The tier as written.
    let tier: String
    /// The function as named; nil on interaction rows.
    let primaryFunctionName: String?
    /// An interaction row's reducer.
    let reducerQualifiedName: String?
    /// `<absolute file>:<line>`, `(unknown)` or `<corpus>:0`.
    let location: String
    /// The declaring type's bare name.
    let typeName: String?
    /// The declaring type's lexical path.
    let qualifiedTypeName: String?
    /// The second function of a pair.
    let secondaryFunctionName: String?
    /// Why no test can run the law as written.
    let structuralBlocker: String?
    /// Whether the subject is a computed property.
    let isComputedProperty: Bool
    /// Whether the row carries a type shape.
    let hasTypeShape: Bool
    /// Every field but the unstable ones.
    let fields: JSONValue

    /// Decodes a row, keeping its stable fields whole for comparison.
    init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        identityHash = try container.decode(String.self, forKey: .identityHash)
        templateName = try container.decodeIfPresent(String.self, forKey: .templateName)
        family = try container.decodeIfPresent(String.self, forKey: .family)
        score = try container.decode(Int.self, forKey: .score)
        tier = try container.decode(String.self, forKey: .tier)
        primaryFunctionName = try container.decodeIfPresent(String.self, forKey: .primaryFunctionName)
        reducerQualifiedName = try container.decodeIfPresent(String.self, forKey: .reducerQualifiedName)
        location = try container.decode(String.self, forKey: .location)
        typeName = try container.decodeIfPresent(String.self, forKey: .typeName)
        qualifiedTypeName = try container.decodeIfPresent(String.self, forKey: .qualifiedTypeName)
        secondaryFunctionName = try container.decodeIfPresent(String.self, forKey: .secondaryFunctionName)
        structuralBlocker = try container.decodeIfPresent(String.self, forKey: .structuralBlocker)
        isComputedProperty = try container.decodeIfPresent(Bool.self, forKey: .isComputedProperty) ?? false
        hasTypeShape = try container.contains(.typeShape) && container.decodeNil(forKey: .typeShape) == false
        guard case .object(var members) = try JSONValue(from: decoder) else {
            throw DecodingError.dataCorruptedError(
                forKey: .identityHash,
                in: container,
                debugDescription: "a row is not an object"
            )
        }
        for key in Self.unstableKeys {
            members[key] = nil
        }
        fields = .object(members)
    }

    /// This row as `population` written by `target`, its location made
    /// relative to `root`, the directory the tool ran in.
    func row(_ population: PropertyCandidate.Population, target: String, root: URL) -> SwiftInferRow {
        SwiftInferRow(
            population: population,
            identity: identityHash,
            template: templateName ?? family ?? "",
            tier: tier,
            score: score,
            function: primaryFunctionName ?? reducerQualifiedName ?? "",
            typeName: qualifiedTypeName ?? typeName,
            location: SwiftInferIndex.relative(location, under: root),
            isComputedProperty: isComputedProperty,
            partner: secondaryFunctionName,
            blocker: structuralBlocker,
            hasTypeShape: hasTypeShape,
            fields: fields,
            target: target
        )
    }
}
