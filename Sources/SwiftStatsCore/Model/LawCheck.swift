//
//  LawCheck.swift
//  SwiftStatsCore
//
//  One production type's conformance to a protocol SwiftPropertyLaws can
//  check (PRD §7.11), and whether the package's tests check its laws: by a
//  `check<P>PropertyLaws` call, by `@PropertyLawSuite`, or not at all. A
//  `swiftstats` measurement: the protocol table is compiled in.
//

/// A (type, protocol) pair the kit covers, and its law-check state.
public struct LawCheck: Codable, Hashable, Sendable {
    private enum CodingKeys: String, CodingKey {
        case evidence, file, generated, implementation, line, provenance, state, type
        case protocolName = "protocol"
    }

    /// How the type comes to conform.
    public enum Provenance: String, Codable, CaseIterable, Sendable {
        /// An inheritance clause names the protocol.
        case declared
        /// A raw-value enum, which is `RawRepresentable` without naming it.
        case rawValueEnum = "rawType"
        /// `Encodable` and `Decodable` named separately, which make `Codable`.
        case codable
    }

    /// Whether the conformance's witnesses are written by hand.
    public enum Implementation: String, Codable, CaseIterable, Sendable {
        /// The type or one of its extensions writes a witness the laws test
        /// (`==`, `hash(into:)`, `<`, `encode(to:)`, …), the type is a class
        /// (for `Equatable` and `Hashable`), or the protocol is one the
        /// compiler never synthesises.
        case custom
        /// The compiler synthesises every witness the laws test.
        case synthesized
    }

    /// Whether the package's tests check the pair's laws, the first that applies.
    public enum State: String, Codable, CaseIterable, Sendable {
        /// The discovery plugin's generated file replaces the check with a
        /// user's suppression marker.
        case suppressed
        /// A test calls the check, or `@PropertyLawSuite` emits it.
        case run
        /// A `FloatingPoint` or `BinaryFloatingPoint` check runs, and the kit
        /// waives this protocol's laws for floating-point types by design.
        case waived
        /// Nothing in the package checks it.
        case unchecked = "notRun"
    }

    /// What shows a pair suppressed or run.
    public enum Evidence: String, Codable, CaseIterable, Sendable {
        /// A suppression marker in the discovery plugin's generated file.
        case marker
        /// A `check<P>PropertyLaws` call in a test target.
        case call
        /// `@PropertyLawSuite` on the type's primary declaration.
        case macro
    }

    /// The type, as `Module::Name` with its lexical path.
    public let type: String
    /// The protocol, as the kit names it (`Hashable`, `Semigroup`).
    public let protocolName: String
    /// How the type comes to conform.
    public let provenance: Provenance
    /// Whether its witnesses are written by hand.
    public let implementation: Implementation
    /// Whether the package's tests check it.
    public let state: State
    /// What shows it suppressed or run; nil when waived or not run.
    public let evidence: Evidence?
    /// The file of the declaration that first makes the type conform: its
    /// primary declaration, else its first extension in path order.
    public let file: String
    /// That declaration's first line.
    public let line: Int
    /// Whether that file is generated (PRD D8).
    public let generated: Bool

    /// The module of `type`.
    var module: String {
        type.components(separatedBy: "::").first ?? type
    }

    /// Creates a pair. Fields are documented on their properties.
    public init(
        type: String,
        protocolName: String,
        provenance: Provenance,
        implementation: Implementation,
        state: State,
        evidence: Evidence?,
        file: String,
        line: Int,
        generated: Bool
    ) {
        self.type = type
        self.protocolName = protocolName
        self.provenance = provenance
        self.implementation = implementation
        self.state = state
        self.evidence = evidence
        self.file = file
        self.line = line
        self.generated = generated
    }
}
