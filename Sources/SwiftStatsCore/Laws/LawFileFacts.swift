//
//  LawFileFacts.swift
//  SwiftStatsCore
//
//  What law detection reads from one file (PRD §7.11): its type
//  declarations, extensions and typealiases, with their inheritance and the
//  witnesses they write; the `==` and `<` it declares at file scope; its kit
//  protocol checks if it is in a test target; and its suppression markers
//  if the discovery plugin generated it.
//

/// The law-detection facts of one source file.
struct LawFileFacts {
    /// A witness the laws test, written in a type or extension body.
    enum Witness: Hashable {
        /// `static func ==`.
        case equalTo
        /// `static func <`.
        case lessThan
        /// `func hash(into:)`.
        case hashInto
        /// `var hashValue`.
        case hashValue
        /// `func encode(to:)`.
        case encodeTo
        /// `init(from:)`.
        case initFrom
        /// A nested `CodingKeys` type.
        case codingKeys
        /// `init(rawValue:)` or `init?(rawValue:)`.
        case initRawValue
        /// `var rawValue`.
        case rawValue
        /// `static var allCases`.
        case allCases
    }

    /// A type declaration or extension outside any function body.
    struct Declaration {
        /// What it declares.
        let kind: TypeKind
        /// The lexical path; for an extension, the extended type as written,
        /// generic arguments stripped. A type nested in an extension takes
        /// the extended type's path without a package module qualifier, so
        /// `Currency` in `extension Core.Money` is `Money.Currency`.
        let name: String
        /// Its first line.
        let line: Int
        /// Its inheritance clause's names, normalised, in written order.
        let inherited: [String]
        /// Its inheritance clause's entries exactly as written, trimmed, in
        /// written order: `@PropertyLawSuite` matches these, so
        /// `Swift.Hashable` or `Codable & Hashable` names nothing to it.
        let writtenInherited: [String]
        /// Whether `@PropertyLawSuite` is attached.
        let hasSuite: Bool
        /// The witnesses directly in its body, `#if` branches included.
        let witnesses: Set<Witness>
        /// Whether only its file can see it: it, or a type or extension
        /// around it, is `private` or `fileprivate`, or an extension around
        /// it extends a type that is. For an extension, whether what it
        /// declares is.
        let fileScoped: Bool
        /// The names its body can use for types it doesn't declare: a
        /// generic type's parameters, a protocol's associated types, the
        /// constrained names of an extension's `where` clause.
        let generics: [String]
    }

    /// A `typealias` outside any function body.
    struct Alias {
        /// Its lexical path, as a declaration's.
        let name: String
        /// The type it names: a dotted path with generic arguments
        /// stripped, else its value as written.
        let value: String
        /// Whether only its file can see it, as a declaration.
        let fileScoped: Bool
    }

    /// An `==` or `<` declared at file scope with both parameters of one
    /// type, which Swift finds as that type's witness where it is visible.
    struct OperatorWitness {
        /// The parameters' type as written, generic arguments stripped.
        let typeName: String
        /// The witness it is.
        let witness: Witness
        /// Whether it is `private` or `fileprivate`, so only its file sees it.
        let fileScoped: Bool
    }

    /// A `check<P>PropertyLaws` call for a protocol in the kit's table.
    struct Call {
        /// The protocol it checks.
        let protocolName: String
        /// Its subject as written, generic arguments stripped, through any
        /// typealias declared in a function body or closure around it; nil
        /// when no argument names one, it is a generic parameter or `Self`,
        /// or such a typealias names no plain type.
        let typeName: String?
        /// The lexical path of the type or extension around the call.
        let scope: [String]
        /// Whether it passes `laws: .ownOnly`, so it checks `protocolName` alone.
        let ownOnly: Bool
        /// Whether its subject names a type declared in a function body or
        /// closure around the call, or nested in one: never a subject.
        let namesLocalType: Bool
    }

    /// A suppression marker, `// (check<P>PropertyLaws for <T> suppressed by user marker)`.
    struct Marker {
        /// The protocol whose check it replaces.
        let protocolName: String
        /// The type as the marker writes it.
        let typeName: String
    }

    /// The target the file belongs to.
    let module: String
    /// Path of the file, relative to the package root.
    let file: String
    /// Whether the target is a test target.
    let isTest: Bool
    /// Whether the file imports a module exporting the kit's protocols.
    let importsKit: Bool
    /// Its type declarations and extensions, local ones left out, in source order.
    let declarations: [Declaration]
    /// Its typealiases, local ones left out, in source order.
    let aliases: [Alias]
    /// Its file-scope `==` and `<` witnesses, in source order.
    let operatorWitnesses: [OperatorWitness]
    /// Its kit protocol checks; only a test target's are collected.
    let calls: [Call]
    /// Its suppression markers; only a file the discovery plugin generated has any.
    let markers: [Marker]
}
