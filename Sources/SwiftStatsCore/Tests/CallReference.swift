//
//  CallReference.swift
//  SwiftStatsCore
//
//  A call a test or a test helper writes, or an unapplied reference written
//  with its argument labels (`f(a:b:)`), as tests per public function read
//  it (M5): the base name, what it is written on, and its arguments or
//  labels. An initialiser's call is written by its type's name: `T(…)`,
//  `T<U>(…)` and `A.T(…)` give `T`, as does `T.init(…)` with
//  `isInitializer` set, and so does an implicit `.init(…)` that
//  initialises a binding annotated with `T`. The receiver is then the
//  type's written qualifier. A call of the enclosing type, `Self(…)`,
//  `Self.init(…)` or `self.init(…)`, is written by the name `Self` until
//  the type of the test or helper writing it resolves it
//  (`resolvingSelf(as:)`). Names are without backticks.
//

/// A call or labelled reference.
struct CallReference: Hashable, Sendable {
    /// What a call is written on.
    enum Receiver: Hashable, Sendable {
        /// Nothing: `f(…)`, `T(…)`.
        case bare
        /// An expression other than a chain of names: `f().g(…)`, `x?.g(…)`.
        case expression
        /// An implicit member: `.f(…)`.
        case implicit
        /// The enclosing type or instance: `self.f(…)`, `Self.f(…)`,
        /// `super.f(…)`.
        case selfReference
        /// A chain of names: `x.f(…)` gives `["x"]`, `A.B.f(…)` `["A", "B"]`.
        case path([String])
    }

    /// How it is written.
    enum Shape: Hashable, Sendable {
        /// Applied to these arguments, the trailing closures last.
        case applied([CallArgument])
        /// Unapplied, with these labels, nil for `_`.
        case labelled([String?])
    }

    /// The name a call of the enclosing type is written by until it is
    /// resolved (`resolvingSelf(as:)`); no type can be named `Self`.
    static let enclosingType = "Self"

    /// The base name, or the type's name for an initialiser.
    let name: String
    /// What it is written on.
    let receiver: Receiver
    /// Whether it is written `init`: `T.init(…)` or an implicit `.init(…)`.
    let isInitializer: Bool
    /// Its arguments or labels.
    let shape: Shape

    /// Whether it is written on something: not bare.
    var isMember: Bool {
        receiver != .bare
    }

    /// Whether its arguments fit `signature`, or its labels name it.
    func fits(_ signature: CallSignature) -> Bool {
        switch shape {
        case .applied(let arguments):
            signature.accepts(arguments)

        case .labelled(let labels):
            signature.isNamed(by: labels)
        }
    }

    /// Whether it is written on nothing, or on a chain of names that is a
    /// suffix of `allowed` (`TypePathMatch`).
    func isQualified(within allowed: [String]) -> Bool {
        switch receiver {
        case .bare:
            true

        case .path(let written):
            TypePathMatch.isSuffix(written, of: allowed)

        case .expression, .implicit, .selfReference:
            false
        }
    }

    /// This call, a call of the enclosing type written where the type at
    /// `typePath` (its components) encloses it, as a call of that type,
    /// qualified by the path's other components; any other call as it is.
    func resolvingSelf(as typePath: [String]) -> Self {
        guard name == Self.enclosingType, receiver == .bare, let type = typePath.last else {
            return self
        }
        let qualifier = Array(typePath.dropLast())
        return Self(
            name: type,
            receiver: qualifier.isEmpty ? .bare : .path(qualifier),
            isInitializer: isInitializer,
            shape: shape
        )
    }
}
