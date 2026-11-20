//
//  StoredEffect.swift
//  SwiftStatsCore
//
//  A function row's side-effect columns (store v3, PRD §7.10): the
//  resolved tier and its source, purity, the refutation's innermost cause,
//  and for a `func` its body inference and value shape. Grouped as the
//  record's `EffectFacts` are, so a row needs no optional Booleans.
//

/// The side-effect columns of one function row.
public struct StoredEffect: Hashable, Sendable {
    /// The resolved tier (`effectTier`); nil for a conflicting, unknown or
    /// unresolved source.
    public let tier: EffectFacts.Tier?
    /// Where the tier comes from (`effectSource`).
    public let source: EffectFacts.Source
    /// The purity verdict (`purity`).
    public let purity: EffectFacts.Purity
    /// The refutation's innermost cause, as SwiftEffectInference names the
    /// case (`refutation`); nil unless purity is refuted.
    public let refutation: String?
    /// Body inference and value shape (`inference`, `inferredTier`,
    /// `inferredAnchor`, `inferredDepth`, `inferredVia`, `valueShaped`,
    /// `shape`); `func` only.
    public let function: EffectFacts.Function?

    /// The columns of `facts`.
    init(_ facts: EffectFacts) {
        tier = facts.tier
        source = facts.source
        purity = facts.purity
        refutation = facts.refutation?.root
        function = facts.function
    }

    /// Creates the columns. Fields are documented on their properties.
    init(
        tier: EffectFacts.Tier?,
        source: EffectFacts.Source,
        purity: EffectFacts.Purity,
        refutation: String?,
        function: EffectFacts.Function?
    ) {
        self.tier = tier
        self.source = source
        self.purity = purity
        self.refutation = refutation
        self.function = function
    }
}
