//
//  TypeIdentity.swift
//  SwiftStatsCore
//
//  How the scan names a type of the package (M7, design §4.3, §9.1's
//  `typeIndex` key): its target, its type path as its type record writes
//  it, and its file when it is `private` or `fileprivate` (empty
//  otherwise, local types included), as `TypeOwner` tells file-scoped
//  types apart.
//

/// A type's target, path and, when file-scoped, file.
struct TypeIdentity: Hashable, Sendable {
    /// The identity of a type that isn't the package's: every part empty.
    static let unknown = Self(module: "", typePath: "", typeFile: "")

    /// The type's target.
    let module: String
    /// Its type path.
    let typePath: String
    /// Its file when file-scoped; empty otherwise.
    let typeFile: String

    /// The identity's parts, in order, for comparing.
    var parts: [String] {
        [module, typePath, typeFile]
    }

    /// The file as the scan JSON writes it: nil when not file-scoped.
    var writtenFile: String? {
        typeFile.isEmpty ? nil : typeFile
    }

    /// An identity of the parts given.
    init(module: String, typePath: String, typeFile: String) {
        self.module = module
        self.typePath = typePath
        self.typeFile = typeFile
    }

    /// The identity of `type`, whose file declares the file-scoped types
    /// `fileScopedTypes` (dotted paths, as `FileScopedTypes` finds them).
    init(_ type: TypeRecord, fileScopedTypes: Set<String>) {
        module = type.module
        typePath = type.name
        let isFileScoped = type.isLocal == false && FileScopedTypes.isFileScoped(type.name, in: fileScopedTypes)
        typeFile = isFileScoped ? type.file : ""
    }

    /// Whether this type is nested in `outer` (design §4.3): in the same
    /// target, its type path `outer`'s followed by `.`, and `outer` either
    /// not file-scoped or file-scoped in this type's file. A type nested in
    /// a file-scoped type is file-scoped in the same file, but a `private`
    /// type nested in a plain one, or declared in a `private extension` of
    /// it, is file-scoped while its enclosing type isn't.
    func isNested(in outer: Self) -> Bool {
        module == outer.module
            && (outer.typeFile.isEmpty || outer.typeFile == typeFile)
            && typePath.hasPrefix(outer.typePath + ".")
    }
}
