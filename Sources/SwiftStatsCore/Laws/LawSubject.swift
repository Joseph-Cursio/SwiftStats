//
//  LawSubject.swift
//  SwiftStatsCore
//
//  One production struct, class, enum or actor and the declarations that
//  make it conform (PRD §7.11): its primary declarations (several under
//  `#if`, in one file when only that file can see the type) and the
//  production extensions resolving to it, with the file-scope `==` and `<`
//  that are its witnesses. Its pairs are the
//  kit protocols these name, a raw-value enum's `RawRepresentable`, and
//  `Codable` from `Encodable` and `Decodable` named separately; protocols
//  a named protocol implies are not pairs.
//

/// A type whose conformances law detection reads.
struct LawSubject {
    /// A declaration of the type or an extension of it.
    struct Site {
        /// The module of its file.
        let module: String
        /// Path of its file.
        let file: String
        /// Whether its file imports a module exporting the kit's protocols.
        let importsKit: Bool
        /// The declaration itself.
        let declaration: LawFileFacts.Declaration

        /// The site of `declaration` in `facts`.
        init(_ declaration: LawFileFacts.Declaration, in facts: LawFileFacts) {
            module = facts.module
            file = facts.file
            importsKit = facts.importsKit
            self.declaration = declaration
        }

        /// Path order, then line.
        static func precedes(_ lhs: Self, _ rhs: Self) -> Bool {
            (lhs.file, lhs.declaration.line) < (rhs.file, rhs.declaration.line)
        }
    }

    /// A protocol the type conforms to, how, and where that is first declared.
    struct Pair {
        /// The protocol, as the kit names it.
        let protocolName: String
        /// How the type comes to conform.
        let provenance: LawCheck.Provenance
        /// The first declaration that makes it conform.
        let site: Site
    }

    /// A file-scope `==` or `<` taking two of the type, and where it is declared.
    struct Operator {
        /// The witness it is.
        let witness: LawFileFacts.Witness
        /// The module that declares it.
        let module: String
        /// The file that declares it.
        let file: String
        /// Whether it is `private` or `fileprivate`.
        let fileScoped: Bool

        /// Whether a conformance declared at `site` sees it, which Swift
        /// requires of a witness: in the same module, and in the same file
        /// when only its file can see it. A module never sees one declared
        /// in a module depending on it.
        func isVisible(from site: Site) -> Bool {
            site.module == module && (fileScoped == false || site.file == file)
        }
    }

    /// The type.
    let type: LawTypeResolver.TypeName
    /// Its primary declarations, in path order.
    var primaries: [Site] = []
    /// Its extensions, in path order.
    var extensions: [Site] = []
    /// The `==` and `<` production files declare for it at file scope.
    var operators: [Operator] = []

    /// Primaries first, then extensions.
    var sites: [Site] {
        primaries.sorted(by: Site.precedes) + extensions.sorted(by: Site.precedes)
    }

    /// The first primary declaring an enum whose first inherited name is a
    /// raw type, which makes it `RawRepresentable`.
    var rawValueEnum: Site? {
        primaries.sorted(by: Site.precedes).first { site in
            site.declaration.kind == .enumType
                && KitProtocols.rawValueTypes.contains(site.declaration.inherited.first ?? "")
        }
    }

    /// Whether a primary declares a class, which can't synthesise `==` or hashing.
    var isClass: Bool {
        primaries.contains { $0.declaration.kind == .classType }
    }

    /// The witnesses its primaries and extensions write, and those
    /// declared for it at file scope that a conformance at `site` sees.
    func witnesses(seenFrom site: Site) -> Set<LawFileFacts.Witness> {
        let visible = operators.filter { $0.isVisible(from: site) }.map(\.witness)
        return sites.reduce(into: Set(visible)) { result, declaring in
            result.formUnion(declaring.declaration.witnesses)
        }
    }

    /// The kit protocols it conforms to, ignoring a kit algebraic protocol
    /// named in a file that doesn't import the kit or named in `blocked`,
    /// the algebraic names the package declares a protocol for itself.
    func pairs(blocked: Set<String>) -> [Pair] {
        var pairs: [Pair] = []
        var declared: Set<String> = []
        var encodable = false
        var decodable = false
        var codableSite: Site?
        for site in sites {
            for name in site.declaration.inherited {
                let isVisible = KitProtocols.algebraic.contains(name) == false
                    || (site.importsKit && blocked.contains(name) == false)
                if KitProtocols.knownSet.contains(name), declared.contains(name) == false, isVisible {
                    declared.insert(name)
                    pairs.append(Pair(protocolName: name, provenance: .declared, site: site))
                }
                encodable = encodable || name == "Encodable"
                decodable = decodable || name == "Decodable"
                if name == "Encodable" || name == "Decodable" {
                    codableSite = codableSite ?? site
                }
            }
        }
        if declared.contains("RawRepresentable") == false, let primary = rawValueEnum {
            pairs.append(Pair(protocolName: "RawRepresentable", provenance: .rawValueEnum, site: primary))
        }
        if declared.contains("Codable") == false, encodable, decodable, let codableSite {
            pairs.append(Pair(protocolName: "Codable", provenance: .codable, site: codableSite))
        }
        return pairs
    }

    /// Whether the type writes its own witnesses for `pair`'s laws.
    func implementation(of pair: Pair) -> LawCheck.Implementation {
        let written = witnesses(seenFrom: pair.site)
        let isCustom: Bool
        switch pair.protocolName {
        case "Equatable":
            isCustom = isClass || written.contains(.equalTo)

        case "Hashable":
            isCustom = isClass || written.isDisjoint(with: [.hashInto, .hashValue, .equalTo]) == false

        case "Comparable":
            isCustom = written.contains(.lessThan)

        case "Codable":
            isCustom = written.isDisjoint(with: [.encodeTo, .initFrom, .codingKeys]) == false

        case "RawRepresentable":
            isCustom = pair.provenance == .declared || written.isDisjoint(with: [.initRawValue, .rawValue]) == false

        case "CaseIterable":
            isCustom = written.contains(.allCases)

        default:
            isCustom = true
        }
        return isCustom ? .custom : .synthesized
    }
}
