//
//  MarkdownSignals+Columns.swift
//  SwiftStatsCore
//
//  The input columns of M4's signal tables (PRD §8): what each reads from
//  an item's payloads. A cell whose payload is absent shows a dash.
//

extension MarkdownSignals {
    /// A column: its heading, and how a cell reads an item.
    typealias Column = (String, (SignalItem) -> String)

    /// Untested property: the suggestion and what was decided about it.
    static var untestedPropertyColumns: [Column] {
        [
            ("Template", property(\.template)),
            ("Tier / score", property { "\($0.tier) / \($0.score)" }),
            ("Verified", property { $0.verified ? "yes" : "no" }),
            ("Blocked", property { $0.blocked ? "yes" : "no" }),
            ("Partner", property { $0.partner ?? "—" }),
            ("Decision", property { $0.decision?.rawValue ?? "—" })
        ]
    }

    /// Tool disagreement: the suggestion, and what the body inference rests
    /// on. Purity is blank when pure.
    static var toolDisagreementColumns: [Column] {
        [
            ("Template", property(\.template)),
            ("SIP tier / score", property { "\($0.tier) / \($0.score)" }),
            ("Via", inferred { $0.via.joined(separator: "; ") }),
            ("Anchor", inferred(\.anchor.rawValue)),
            ("Depth", inferred { String($0.depth) }),
            ("Source", effect(\.source.rawValue)),
            ("Purity", effect { $0.purity == .pure ? "" : $0.purity.rawValue })
        ]
    }

    /// Missing template: the shape and size of the function.
    static var missingTemplateColumns: [Column] {
        [
            ("Shape", effect { $0.shape?.rawValue ?? "—" }),
            ("Purity", effect(\.purity.rawValue)),
            ("Body lines", function { String($0.bodyLines) }),
            ("Cognitive", function { MarkdownNumber.optional($0.cognitive) })
        ]
    }

    /// Unchecked laws: the protocols, and what to do about them.
    static var uncheckedLawsColumns: [Column] {
        [
            ("Protocols", laws { $0.protocols.joined(separator: ", ") }),
            ("Action", laws(action))
        ]
    }

    /// What to do about unchecked pairs: call the kit's checks, or first
    /// depend on the kit.
    private static func action(_ laws: SignalItem.Laws) -> String {
        laws.kitDependency ? "add `check<P>PropertyLaws` calls" : "add the SwiftPropertyLaws dependency"
    }

    /// A cell reading an item's suggestion with `cell`.
    private static func property(_ cell: @escaping (SignalItem.Property) -> String) -> (SignalItem) -> String {
        { item in item.property.map(cell) ?? "—" }
    }

    /// A cell reading an item's effect facts with `cell`.
    private static func effect(_ cell: @escaping (SignalItem.Effect) -> String) -> (SignalItem) -> String {
        { item in item.effect.map(cell) ?? "—" }
    }

    /// A cell reading an item's body-inferred tier with `cell`.
    private static func inferred(_ cell: @escaping (EffectFacts.Inferred) -> String) -> (SignalItem) -> String {
        { item in item.effect?.inferred.map(cell) ?? "—" }
    }

    /// A cell reading an item's function size with `cell`.
    private static func function(_ cell: @escaping (SignalItem.Function) -> String) -> (SignalItem) -> String {
        { item in item.function.map(cell) ?? "—" }
    }

    /// A cell reading an item's law pairs with `cell`.
    private static func laws(_ cell: @escaping (SignalItem.Laws) -> String) -> (SignalItem) -> String {
        { item in item.laws.map(cell) ?? "—" }
    }
}
