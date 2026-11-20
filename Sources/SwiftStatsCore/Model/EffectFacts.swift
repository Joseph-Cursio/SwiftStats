//
//  EffectFacts.swift
//  SwiftStatsCore
//
//  What SwiftEffectInference says about one production record (PRD §7.10):
//  its declared tier, its purity, the tier inferred from its body, and the
//  shape facts the side-effect signals filter on. Absent optionals are
//  omitted; what a kind doesn't have is grouped, so a subscript has no
//  `declaration` and only a `func` has `function`: nil means "not collected
//  for this kind", never "no". Grouping, rather than PRD-flat fields, keeps
//  `unknown`, `clockDeterministic` and `valueShaped` plain Booleans with no
//  optional-Boolean third state.
//

/// The side-effect facts of one production `func`, computed-property getter
/// or `subscript`.
public struct EffectFacts: Codable, Hashable, Sendable {
    /// A retry-safety tier, from most to least safe.
    public enum Tier: String, Codable, CaseIterable, Sendable {
        /// No observable effect.
        case pure
        /// Effects only an observer sees, such as logging.
        case observational
        /// Running it twice is the same as running it once.
        case idempotent
        /// Idempotent given a deduplication key the caller supplies.
        case externallyIdempotent = "externally_idempotent"
        /// Running it twice differs from running it once.
        case nonIdempotent = "non_idempotent"
    }

    /// Where the resolved tier comes from: the first of these that applies.
    public enum Source: String, Codable, CaseIterable, Sendable {
        /// The attribute and the doc comment declare different tiers; no tier.
        case conflicting
        /// `@EffectUnknown` (or `/// @lint.effect unknown`); no tier.
        case unknown
        /// An attribute or doc comment declares the tier.
        case declared
        /// The purity verdict is `pure`, which gives tier `pure`.
        case purity
        /// The tier SwiftStats inferred from the body.
        case bodyInferred = "bodyInferred"
        /// Nothing gives a tier.
        case unresolved = "none"
    }

    /// SwiftEffectInference's purity verdict. It checks I/O,
    /// nondeterminism, traps and `async`, never state mutation.
    public enum Purity: String, Codable, CaseIterable, Sendable {
        /// Nothing refutes purity.
        case pure
        /// Pure but for errors it throws itself (a `throws` function with no `try`).
        case pureButPartial = "pure_but_partial"
        /// Something in the declaration refutes purity.
        case refuted
    }

    /// Whether body inference could give this declaration a tier of its own.
    public enum Inference: String, Codable, CaseIterable, Sendable {
        /// Its signature is held by no other declaration; `inferred` is its own.
        case unique
        /// Several bodied declarations share its signature, so no tier is its own.
        case ambiguous
        /// Another declaration annotates its signature, which suppresses inference.
        case shadowed
        /// It declares a tier itself.
        case annotated
    }

    /// What an inferred tier rests on.
    public enum Anchor: String, Codable, CaseIterable, Sendable {
        /// Every step is an annotation.
        case declared
        /// At least one step is a name or framework heuristic.
        case heuristic
    }

    /// Which algebraic shape a value-shaped function has.
    public enum Shape: String, Codable, CaseIterable, Sendable {
        /// One parameter, returning its type.
        case endomorphism
        /// Two parameters of the return type.
        case binary = "binaryOperation"
        /// A non-mutating instance method returning the enclosing type.
        case selfReturning = "selfReturning"
        /// One or two parameters of one type, returning `Bool`.
        case predicate
    }

    /// Why purity was refuted. Positions are dropped: a construction's cause
    /// can sit in another file.
    public struct Refutation: Codable, Hashable, Sendable {
        /// The outer case's name, such as `refutingConstruction`.
        public let `case`: String
        /// The innermost cause's case name, following `cause:` chains; the
        /// outer case when there is no chain.
        public let root: String
        /// SwiftEffectInference's description of the whole chain.
        public let detail: String

        /// Creates a refutation. Fields are documented on their properties.
        public init(case: String, root: String, detail: String) {
            self.case = `case`
            self.root = root
            self.detail = detail
        }
    }

    /// The tier SwiftStats inferred from a body, with what it rests on.
    public struct Inferred: Codable, Hashable, Sendable {
        /// The inferred tier.
        public let tier: Tier
        /// Hops back to an anchor. It depends on how many passes ran, so it
        /// is recorded but never ranked or diffed.
        public let depth: Int
        /// Whether the chain rests on annotations alone or on a heuristic.
        public let anchor: Anchor
        /// Up to three reasons for the tier, sorted: a heuristic's own reason,
        /// or ``calls `<signature>` `` for a callee whose tier it took.
        public let via: [String]

        /// Creates an inferred tier. Fields are documented on their properties.
        public init(tier: Tier, depth: Int, anchor: Anchor, via: [String]) {
            self.tier = tier
            self.depth = depth
            self.anchor = anchor
            self.via = via
        }
    }

    /// What a `func` or a computed property declares about its effect.
    public struct Declaration: Codable, Hashable, Sendable {
        /// The declared tier, when one is declared without conflict.
        public let declared: Tier?
        /// The deduplication key's parameter, for a declared `externally_idempotent`.
        public let keyParameter: String?
        /// Whether it declares `@EffectUnknown`.
        public let unknown: Bool
        /// Whether it declares `@ClockDeterministic`.
        public let clockDeterministic: Bool

        /// Creates a declaration. Fields are documented on their properties.
        public init(declared: Tier?, keyParameter: String?, unknown: Bool, clockDeterministic: Bool) {
            self.declared = declared
            self.keyParameter = keyParameter
            self.unknown = unknown
            self.clockDeterministic = clockDeterministic
        }
    }

    /// What only a `func` has: body inference and its value shape.
    public struct Function: Codable, Hashable, Sendable {
        /// Whether body inference could give a tier of its own; nil for a
        /// function declared inside a closure, which inference never visits.
        public let inference: Inference?
        /// The body-inferred tier, for a `unique` function whose body
        /// resolved a callee.
        public let inferred: Inferred?
        /// Whether the function returns a value and writes no state outside
        /// its own parameters and locals.
        public let valueShaped: Bool
        /// The function's algebraic shape, when it is value-shaped and has one.
        public let shape: Shape?

        /// Creates function facts. Fields are documented on their properties.
        public init(inference: Inference?, inferred: Inferred?, valueShaped: Bool, shape: Shape?) {
            self.inference = inference
            self.inferred = inferred
            self.valueShaped = valueShaped
            self.shape = shape
        }
    }

    /// The resolved tier; nil for a conflicting, unknown or unresolved source.
    public let tier: Tier?
    /// Where `tier` comes from.
    public let source: Source
    /// What the declaration declares; nil for a subscript, whose
    /// annotations SwiftEffectInference doesn't read.
    public let declaration: Declaration?
    /// The purity verdict.
    public let purity: Purity
    /// Why purity was refuted, when it was.
    public let refutation: Refutation?
    /// Body inference and value shape; `func` only.
    public let function: Function?

    /// Creates facts. Fields are documented on their properties.
    public init(
        tier: Tier?,
        source: Source,
        declaration: Declaration?,
        purity: Purity,
        refutation: Refutation?,
        function: Function?
    ) {
        self.tier = tier
        self.source = source
        self.declaration = declaration
        self.purity = purity
        self.refutation = refutation
        self.function = function
    }
}
