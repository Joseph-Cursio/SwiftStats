//
//  LawSubject.swift
//  SwiftStatsCore
//
//  One production struct, class, enum or actor and the declarations that
//  make it conform (PRD §7.11): its primary declarations (several under
//  `#if`) and the production extensions resolving to it. Its pairs are the
//  kit protocols these name, a raw-value enum's `RawRepresentable`, and
//  `Codable` from `Encodable` and `Decodable` named separately; protocols
//  a named protocol implies are not pairs.
//

/// A type whose conformances law detection reads.
struct LawSubject {
    /// A declaration of the type or an extension of it.
    struct Site {
        /// Path of its file.
        let file: String
        /// Whether its file imports a module exporting the kit's protocols.
        let importsKit: Bool
        /// The declaration itself.
        let declaration: LawFileFacts.Declaration

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

    /// The type.
    let type: LawTypeResolver.TypeName
    /// Its primary declarations, in path order.
    var primaries: [Site] = []
    /// Its extensions, in path order.
    var extensions: [Site] = []

    /// Primaries first, then extensions.
    var sites: [Site] {
        primaries.sorted(by: Site.precedes) + extensions.sorted(by: Site.precedes)
    }

    /// The witnesses its primaries and extensions write.
    var witnesses: Set<LawFileFacts.Witness> {
        sites.reduce(into: []) { result, site in
            result.formUnion(site.declaration.witnesses)
        }
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
        let written = witnesses
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
