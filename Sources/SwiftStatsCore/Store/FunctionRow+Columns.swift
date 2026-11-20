//
//  FunctionRow+Columns.swift
//  SwiftStatsCore
//
//  The `function` table's columns. Written out by hand so the v3 groups
//  flatten into nullable columns: `generated` and the side-effect columns
//  are null on a row written before v3, and a group comes back only when
//  its leading column (`generated`, `effectSource`, `valueShaped`) holds a
//  value. `inferredVia` is newline-joined.
//

extension FunctionRow {
    /// The table's columns.
    private enum CodingKeys: String, CodingKey {
        case accessorKind, bodyHash, bodyLines, cognitive, decisionCount, effectSource, effectTier, endLine, file
        case generated, ifConfig, inference, inferredAnchor, inferredDepth, inferredTier, inferredVia, isAsync
        case isDocumented, key, kind, maxNesting, module, name, parameterCount, parentKey, purity, refutation, role
        case shape, snapshotId, startLine, strippedLines, swiftLintCompatible, valueShaped
    }

    /// Reads a row.
    public init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        snapshotId = try container.decode(Int64.self, forKey: .snapshotId)
        key = try container.decode(String.self, forKey: .key)
        module = try container.decode(String.self, forKey: .module)
        kind = try container.decode(FunctionKind.self, forKey: .kind)
        name = try container.decode(String.self, forKey: .name)
        accessorKind = try container.decodeIfPresent(String.self, forKey: .accessorKind)
        file = try container.decode(String.self, forKey: .file)
        startLine = try container.decode(Int.self, forKey: .startLine)
        endLine = try container.decode(Int.self, forKey: .endLine)
        bodyHash = try container.decode(String.self, forKey: .bodyHash)
        parentKey = try container.decodeIfPresent(String.self, forKey: .parentKey)
        ifConfig = try container.decodeIfPresent(String.self, forKey: .ifConfig)
        role = try container.decode(CodeRole.self, forKey: .role)
        strippedLines = try container.decode(Int.self, forKey: .strippedLines)
        bodyLines = try container.decode(Int.self, forKey: .bodyLines)
        parameterCount = try container.decodeIfPresent(Int.self, forKey: .parameterCount)
        isDocumented = try container.decode(Bool.self, forKey: .isDocumented)
        isAsync = try container.decode(Bool.self, forKey: .isAsync)
        cognitive = try container.decodeIfPresent(Int.self, forKey: .cognitive)
        decisionCount = try container.decodeIfPresent(Int.self, forKey: .decisionCount)
        swiftLintCompatible = try container.decodeIfPresent(Int.self, forKey: .swiftLintCompatible)
        maxNesting = try container.decodeIfPresent(Int.self, forKey: .maxNesting)
        facts = try container.decodeIfPresent(Bool.self, forKey: .generated).map { generated in
            StoredFunctionFacts(generated: generated, effect: try Self.effect(in: container))
        }
    }

    /// The side-effect columns in `container`; nil when `effectSource` is null.
    private static func effect(in container: KeyedDecodingContainer<CodingKeys>) throws -> StoredEffect? {
        guard let source = try container.decodeIfPresent(EffectFacts.Source.self, forKey: .effectSource) else {
            return nil
        }
        return StoredEffect(
            tier: try container.decodeIfPresent(EffectFacts.Tier.self, forKey: .effectTier),
            source: source,
            purity: try container.decode(EffectFacts.Purity.self, forKey: .purity),
            refutation: try container.decodeIfPresent(String.self, forKey: .refutation),
            function: try function(in: container)
        )
    }

    /// The body-inference columns in `container`; nil when `valueShaped` is null.
    private static func function(in container: KeyedDecodingContainer<CodingKeys>) throws -> EffectFacts.Function? {
        guard let valueShaped = try container.decodeIfPresent(Bool.self, forKey: .valueShaped) else {
            return nil
        }
        let inferred = try container.decodeIfPresent(EffectFacts.Tier.self, forKey: .inferredTier).map { tier in
            EffectFacts.Inferred(
                tier: tier,
                depth: try container.decode(Int.self, forKey: .inferredDepth),
                anchor: try container.decode(EffectFacts.Anchor.self, forKey: .inferredAnchor),
                via: try container.decode(String.self, forKey: .inferredVia)
                    .split(separator: "\n")
                    .map(String.init)
            )
        }
        return EffectFacts.Function(
            inference: try container.decodeIfPresent(EffectFacts.Inference.self, forKey: .inference),
            inferred: inferred,
            valueShaped: valueShaped,
            shape: try container.decodeIfPresent(EffectFacts.Shape.self, forKey: .shape)
        )
    }

    /// Writes a row.
    public func encode(to encoder: any Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(snapshotId, forKey: .snapshotId)
        try container.encode(key, forKey: .key)
        try container.encode(module, forKey: .module)
        try container.encode(kind, forKey: .kind)
        try container.encode(name, forKey: .name)
        try container.encodeIfPresent(accessorKind, forKey: .accessorKind)
        try container.encode(file, forKey: .file)
        try container.encode(startLine, forKey: .startLine)
        try container.encode(endLine, forKey: .endLine)
        try container.encode(bodyHash, forKey: .bodyHash)
        try container.encodeIfPresent(parentKey, forKey: .parentKey)
        try container.encodeIfPresent(ifConfig, forKey: .ifConfig)
        try container.encode(role, forKey: .role)
        try container.encode(strippedLines, forKey: .strippedLines)
        try container.encode(bodyLines, forKey: .bodyLines)
        try container.encodeIfPresent(parameterCount, forKey: .parameterCount)
        try container.encode(isDocumented, forKey: .isDocumented)
        try container.encode(isAsync, forKey: .isAsync)
        try container.encodeIfPresent(cognitive, forKey: .cognitive)
        try container.encodeIfPresent(decisionCount, forKey: .decisionCount)
        try container.encodeIfPresent(swiftLintCompatible, forKey: .swiftLintCompatible)
        try container.encodeIfPresent(maxNesting, forKey: .maxNesting)
        try container.encodeIfPresent(facts?.generated, forKey: .generated)
        try encodeEffect(facts?.effect, into: &container)
    }

    /// Writes the side-effect columns of `effect`, all null when it is nil.
    private func encodeEffect(
        _ effect: StoredEffect?,
        into container: inout KeyedEncodingContainer<CodingKeys>
    ) throws {
        try container.encodeIfPresent(effect?.tier, forKey: .effectTier)
        try container.encodeIfPresent(effect?.source, forKey: .effectSource)
        try container.encodeIfPresent(effect?.purity, forKey: .purity)
        try container.encodeIfPresent(effect?.refutation, forKey: .refutation)
        let function = effect?.function
        try container.encodeIfPresent(function?.inference, forKey: .inference)
        try container.encodeIfPresent(function?.inferred?.tier, forKey: .inferredTier)
        try container.encodeIfPresent(function?.inferred?.anchor, forKey: .inferredAnchor)
        try container.encodeIfPresent(function?.inferred?.depth, forKey: .inferredDepth)
        try container.encodeIfPresent(function?.inferred?.via.joined(separator: "\n"), forKey: .inferredVia)
        try container.encodeIfPresent(function?.valueShaped, forKey: .valueShaped)
        try container.encodeIfPresent(function?.shape, forKey: .shape)
    }
}
