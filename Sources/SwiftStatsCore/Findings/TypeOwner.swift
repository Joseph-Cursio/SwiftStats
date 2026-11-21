//
//  TypeOwner.swift
//  SwiftStatsCore
//
//  How a result attached to a type names it (PRD §7.16, M5):
//  `<module>::<type path>`, with ` @ <file>` when the type is `private` or
//  `fileprivate`, so two files' same-named private types never merge.
//

/// The owner text of a type attachment.
enum TypeOwner {
    /// The owner of `type`, whose file declares the file-scoped types
    /// `fileScopedTypes` (dotted paths, as `FileScopedTypes` finds them).
    static func of(_ type: TypeRecord, fileScopedTypes: Set<String>) -> String {
        let owner = "\(type.module)::\(type.name)"
        guard type.isLocal == false, FileScopedTypes.isFileScoped(type.name, in: fileScopedTypes) else {
            return owner
        }
        return owner + " @ " + type.file
    }

    /// The owner of the type a function row's `typePath` names in
    /// `module`, with `typeFile` when the type is file-scoped; nil for a
    /// row outside every type.
    static func of(module: String, typePath: String?, typeFile: String?) -> String? {
        guard let typePath else {
            return nil
        }
        return "\(module)::\(typePath)" + (typeFile.map { " @ \($0)" } ?? "")
    }
}
