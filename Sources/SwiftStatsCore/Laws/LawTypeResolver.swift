//
//  LawTypeResolver.swift
//  SwiftStatsCore
//
//  Resolves a type name written in an extension, a check or a marker to a
//  package type, lexically (PRD §7.11): each prefix of the enclosing type
//  path, innermost outward, joined to the name (in the same module, else in
//  another production module, since an extension's path can name a type
//  declared elsewhere); then the exact name in the same module; then the
//  exact name in another production module. A module-qualified name
//  (`Core.Money`) matches in its module. The first step with any candidate
//  decides: one is the type, several are ambiguous. Nothing falls back to
//  a name's last component.
//

/// Finds which package type a written name means.
struct LawTypeResolver {
    /// A package type: its module and lexical path.
    struct TypeName: Hashable {
        /// The module that declares it.
        let module: String
        /// Its lexical path, dot-separated.
        let name: String

        /// `Module::Name`, as law checks name types.
        var qualified: String {
            "\(module)::\(name)"
        }
    }

    /// What a written name resolves to.
    enum Resolution {
        /// Exactly one package type.
        case resolved(TypeName)
        /// More than one package type at the deciding step.
        case ambiguous
        /// No package type: a foreign or unknown name.
        case foreign
    }

    /// Every declared package type: structs, classes, enums, actors and protocols.
    let types: Set<TypeName>
    /// The production modules, sorted.
    let productionModules: [String]

    /// A resolver over the declarations in `files`.
    init(_ files: [LawFileFacts]) {
        types = Set(files.flatMap { file in
            file.declarations.filter { $0.kind != .extensionDeclaration }.map { declaration in
                TypeName(module: file.module, name: declaration.name)
            }
        })
        productionModules = Set(files.filter { $0.isTest == false }.map(\.module)).sorted()
    }

    /// What `written` means in `module`, inside the types and extensions on `scope`.
    func resolve(_ written: String, in module: String, scope: [String]) -> Resolution {
        let components = scope.flatMap { $0.split(separator: ".").map(String.init) }
        let names = stride(from: components.count, to: 0, by: -1).map { length in
            (components[..<length] + [written]).joined(separator: ".")
        } + [written]
        let otherModules = productionModules.filter { $0 != module }
        for name in names {
            for modules in [[module], otherModules] {
                let found = candidates(name, in: modules)
                if found.isEmpty == false {
                    return decide(found)
                }
            }
        }
        return .foreign
    }

    /// The types `written` names in `modules`, bare or module-qualified.
    private func candidates(_ written: String, in modules: [String]) -> Set<TypeName> {
        modules.reduce(into: []) { result, module in
            let bare = TypeName(module: module, name: written)
            if types.contains(bare) {
                result.insert(bare)
            }
            let qualifier = module + "."
            if written.hasPrefix(qualifier) {
                let qualified = TypeName(module: module, name: String(written.dropFirst(qualifier.count)))
                if types.contains(qualified) {
                    result.insert(qualified)
                }
            }
        }
    }

    /// The resolution `candidates` give.
    private func decide(_ candidates: Set<TypeName>) -> Resolution {
        switch candidates.count {
        case 0:
            return .foreign

        case 1:
            return candidates.first.map(Resolution.resolved) ?? .foreign

        default:
            return .ambiguous
        }
    }
}
