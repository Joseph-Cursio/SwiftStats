//
//  CoverageWitnesses.swift
//  SwiftStatsCore
//
//  Which type paths name protocols, and which members witness a standard
//  protocol's requirement (M5, tests per public function), decided from
//  syntax. A type path names a protocol unless the record's module
//  declares a concrete type of that path. A member witnesses a requirement
//  of a standard protocol its type declares a conformance to anywhere in
//  the module (`StandardProtocols`), or one it inherits from a superclass
//  the module declares; such a member is reached generically. A
//  conformance is read in the module first, then across the package.
//

/// Tells protocols and standard protocols' witnesses apart.
struct CoverageWitnesses {
    /// A type, as its member records name it.
    private struct TypeIdentity: Hashable {
        /// Its module.
        let module: String
        /// Its type path.
        let path: String
    }

    /// Each file's member selectors, by record start.
    private let selectors: [String: [SourcePosition: String]]
    /// Each type's declaration and extension records.
    private let typeRecords: [TypeIdentity: [TypeRecord]]
    /// Each module's protocols and what each refines.
    private let protocols: [TypeIdentity: [String]]
    /// The package's protocols by path, and what each refines in any module.
    private let protocolPaths: [String: [String]]
    /// Each module's structs, classes, enums and actors.
    private let concreteTypes: Set<TypeIdentity>
    /// The paths of the package's structs, classes, enums and actors.
    private let concretePaths: Set<String>

    /// The protocols and witnesses of `measured`.
    init(measured: ScanMeasurements) {
        selectors = measured.selectors
        typeRecords = Dictionary(grouping: measured.types.filter { $0.isLocal == false }) { type in
            TypeIdentity(module: type.module, path: type.name)
        }
        let declaredProtocols = measured.types.filter { $0.kind == .protocolType && $0.isLocal == false }
        protocols = Dictionary(grouping: declaredProtocols) { TypeIdentity(module: $0.module, path: $0.name) }
            .mapValues { $0.flatMap(\.conformances) }
        protocolPaths = Dictionary(grouping: declaredProtocols, by: \.name).mapValues { $0.flatMap(\.conformances) }
        let concrete = measured.types.filter { type in
            type.isLocal == false && type.kind != .protocolType && type.kind != .extensionDeclaration
        }
        concreteTypes = Set(concrete.map { TypeIdentity(module: $0.module, path: $0.name) })
        concretePaths = Set(concrete.map(\.name))
    }

    /// The last component of a type path.
    static func simpleName(of path: String) -> String {
        path.split(separator: ".").last.map(String.init) ?? path
    }

    /// Whether `path`, as `module` writes it, names a protocol: not when
    /// `module` declares a concrete type of that path; otherwise one the
    /// package declares, or a standard one the package declares no type of
    /// that name for.
    func isProtocol(_ path: String, in module: String) -> Bool {
        if concreteTypes.contains(TypeIdentity(module: module, path: path)) {
            return false
        }
        if protocolPaths[path] != nil {
            return true
        }
        return concretePaths.contains(path) == false && StandardProtocols.names.contains(Self.simpleName(of: path))
    }

    /// Whether `record`, a member of the type at `path`, matches a
    /// requirement of a standard protocol its type conforms to, as the
    /// declarations and extensions of the type in the module write it (in
    /// the record's file only for a file-scoped type), refinements, the
    /// package's own protocols and the module's superclasses followed.
    func isWitness(_ record: FunctionRecord, of path: String) -> Bool {
        guard let selector = selectors[record.file]?[record.range.start] else {
            return false
        }
        let declared = (typeRecords[TypeIdentity(module: record.module, path: path)] ?? [])
            .filter { record.typeFile == nil || $0.file == record.typeFile }
            .flatMap(\.conformances)
        var pending = declared
        var seen = Set<String>()
        while let name = pending.popLast() {
            guard seen.insert(name).inserted else {
                continue
            }
            if StandardProtocols.requirements[name]?.contains(selector) == true {
                return true
            }
            pending += StandardProtocols.refinements[name] ?? []
            pending += refinements(of: name, in: record.module)
        }
        return false
    }

    /// What a type conforming to `name`, as `module` writes it, conforms to
    /// through it: when `module` declares a concrete type of that name (a
    /// superclass), what that type's declarations and extensions conform
    /// to, which its subclasses inherit; otherwise what the protocol
    /// refines, `module`'s own protocol of that name, or else any module's.
    private func refinements(of name: String, in module: String) -> [String] {
        let identity = TypeIdentity(module: module, path: name)
        if concreteTypes.contains(identity) {
            return (typeRecords[identity] ?? []).flatMap(\.conformances)
        }
        return protocols[identity] ?? protocolPaths[name] ?? []
    }
}
