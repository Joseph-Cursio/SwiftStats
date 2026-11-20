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
//  (`Core.Money`) matches in its module. Within the same module a type only
//  the name's own file can see comes first: two files may each declare a
//  `private struct Key`, and each is its own type, keyed ` @ <file>` as
//  function keys are (PRD §6.1). A typealias is read through, from where it
//  is declared. The first step with any candidate decides: one type is the
//  type, several are ambiguous. An alias naming a type the step already
//  has is no second candidate, nor is one naming no package type when
//  another candidate does. Nothing falls back to a name's last component.
//

/// Finds which package type a written name means.
struct LawTypeResolver {
    /// A package type: its module, lexical path and, when only its file
    /// can see it, that file.
    struct TypeName: Hashable {
        /// The module that declares it.
        let module: String
        /// Its lexical path, dot-separated.
        let name: String
        /// The file that declares it, when only that file can see it.
        let file: String?

        /// `Module::Name`, as law checks name types, with ` @ <file>` for
        /// a type only its file can see.
        var qualified: String {
            "\(module)::\(name)" + (file.map { " @ \($0)" } ?? "")
        }

        /// The type `name` in `module`; `file` is nil unless only that file can see it.
        init(module: String, name: String, file: String?) {
            self.module = module
            self.name = name
            self.file = file
        }

        /// The type `declaration` of `facts` declares.
        init(_ declaration: LawFileFacts.Declaration, in facts: LawFileFacts) {
            self.init(module: facts.module, name: declaration.name, file: declaration.fileScoped ? facts.file : nil)
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
        /// A package typealias naming no plain type, or aliases that loop.
        case unnamed
    }

    /// A typealias, and where its value is read.
    private struct Alias {
        /// The type it names, as its declaration writes it.
        let value: String
        /// The module that declares it.
        let module: String
        /// The file that declares it.
        let file: String
        /// The lexical path around it.
        let scope: [String]
    }

    /// One step of the search: the modules and which of their names.
    private struct Step {
        /// The modules searched.
        let modules: [String]
        /// The file whose file-scoped names are searched; nil for the
        /// names every file can see.
        let file: String?
    }

    /// How many typealiases a name is read through before it counts as
    /// unnamed, which stops a cycle.
    private static let maximumAliasHops = 8

    /// Every declared package type: structs, classes, enums, actors and protocols.
    let types: Set<TypeName>
    /// The production modules, sorted.
    let productionModules: [String]
    /// The package's typealiases outside function bodies.
    private let aliases: [TypeName: Alias]
    /// The names each type's body can use for types it doesn't declare.
    private let generics: [TypeName: Set<String>]

    /// A resolver over the declarations in `files`.
    init(_ files: [LawFileFacts]) {
        let declared = files.flatMap { file in
            file.declarations.filter { $0.kind != .extensionDeclaration }.map { (TypeName($0, in: file), $0) }
        }
        types = Set(declared.map(\.0))
        generics = declared.reduce(into: [:]) { result, entry in
            result[entry.0, default: []].formUnion(entry.1.generics)
        }
        aliases = files.reduce(into: [:]) { result, file in
            for alias in file.aliases {
                let name = TypeName(module: file.module, name: alias.name, file: alias.fileScoped ? file.file : nil)
                let scope = alias.name.split(separator: ".").dropLast().map(String.init)
                result[name] = result[name]
                    ?? Alias(value: alias.value, module: file.module, file: file.file, scope: scope)
            }
        }
        productionModules = Set(files.filter { $0.isTest == false }.map(\.module)).sorted()
    }

    /// What `written` means in `file` of `module`, inside the types and
    /// extensions on `scope`.
    func resolve(_ written: String, in module: String, file: String, scope: [String]) -> Resolution {
        resolve(written, in: module, file: file, scope: scope, hops: 0)
    }

    /// Whether `name` is a generic parameter or associated type of the type
    /// the outermost entry of `scope` extends or declares, or of a type
    /// around that one: inside `extension LawSuite`, a `Value` the protocol
    /// declares as an associated type names no package type.
    func binds(_ name: String, around scope: [String], in module: String, file: String) -> Bool {
        guard let outermost = scope.first,
              case .resolved(let type) = resolve(outermost, in: module, file: file, scope: []) else {
            return false
        }
        let components = type.name.split(separator: ".").map(String.init)
        return (1...components.count).contains { length in
            let enclosing = components[..<length].joined(separator: ".")
            let names = generics[TypeName(module: type.module, name: enclosing, file: type.file)]
                ?? generics[TypeName(module: type.module, name: enclosing, file: nil)]
            return names?.contains(name) == true
        }
    }

    /// `resolve(_:in:file:scope:)` after `hops` typealiases.
    private func resolve(_ written: String, in module: String, file: String, scope: [String], hops: Int) -> Resolution {
        let components = scope.flatMap { $0.split(separator: ".").map(String.init) }
        let parts = written.split(separator: ".").map(String.init)
        let steps = [
            Step(modules: [module], file: file),
            Step(modules: [module], file: nil),
            Step(modules: productionModules.filter { $0 != module }, file: nil)
        ]
        for length in stride(from: components.count, through: 0, by: -1) {
            let prefix = Array(components[..<length])
            for step in steps {
                let found = candidates((prefix + parts).joined(separator: "."), step: step)
                let aliased = aliasCandidates(prefix: prefix, parts: parts, step: step)
                guard found.isEmpty == false || aliased.isEmpty == false else {
                    continue
                }
                return decide(found: found, aliased: aliased.map { follow($0.alias, rest: $0.rest, hops: hops) })
            }
        }
        return .foreign
    }

    /// What one step means, from the types it finds and what its aliases
    /// name. An alias naming a type the step already has adds nothing, so a
    /// re-export (`typealias Money = Core.Money`) is no rival to its type.
    /// An alias naming no package type is no candidate beside one that
    /// does: `extension Cash { struct Inner }` records `Cash.Inner`, and
    /// reading that through the alias `Cash` names a path no declaration has.
    private func decide(found: Set<TypeName>, aliased: [Resolution]) -> Resolution {
        var meant = found
        var unnamed = 0
        for resolution in aliased {
            switch resolution {
            case .resolved(let named):
                meant.insert(named)

            case .ambiguous:
                return .ambiguous

            case .unnamed:
                unnamed += 1

            case .foreign:
                continue
            }
        }
        switch (meant.first, meant.count + unnamed) {
        case (_, 0):
            return .foreign

        case (.some(let only), 1):
            return .resolved(only)

        case (.none, 1):
            return .unnamed

        default:
            return .ambiguous
        }
    }

    /// The types `written` names in `step`, bare or module-qualified.
    private func candidates(_ written: String, step: Step) -> Set<TypeName> {
        step.modules.reduce(into: []) { result, module in
            for name in names(written, in: module) {
                let type = TypeName(module: module, name: name, file: step.file)
                if types.contains(type) {
                    result.insert(type)
                }
            }
        }
    }

    /// The typealiases a leading part of `parts`, after `prefix`, names in
    /// `step`, with the parts after it.
    private func aliasCandidates(
        prefix: [String],
        parts: [String],
        step: Step
    ) -> [(alias: Alias, rest: ArraySlice<String>)] {
        parts.indices.flatMap { index in
            let written = (prefix + parts[...index]).joined(separator: ".")
            return step.modules.flatMap { module in
                names(written, in: module).compactMap { name in
                    aliases[TypeName(module: module, name: name, file: step.file)].map { alias in
                        (alias, parts[(index + 1)...])
                    }
                }
            }
        }
    }

    /// The names `written` can be in `module`: itself, and without the
    /// module's qualifier when it has one.
    private func names(_ written: String, in module: String) -> [String] {
        let qualifier = module + "."
        return written.hasPrefix(qualifier) ? [written, String(written.dropFirst(qualifier.count))] : [written]
    }

    /// What `alias`, followed by the components `rest`, names.
    private func follow(_ alias: Alias, rest: ArraySlice<String>, hops: Int) -> Resolution {
        guard hops < Self.maximumAliasHops, let value = LawCallReader.typeName(alias.value) else {
            return .unnamed
        }
        let written = ([value] + rest).joined(separator: ".")
        return resolve(written, in: alias.module, file: alias.file, scope: alias.scope, hops: hops + 1)
    }
}
