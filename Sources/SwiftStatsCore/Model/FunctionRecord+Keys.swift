//
//  FunctionRecord+Keys.swift
//  SwiftStatsCore
//
//  Copying a record with new keys, for collision handling.
//

extension FunctionRecord {
    /// This record with `key` and `parentKey` replaced.
    func replacingKeys(key: String, parentKey: String?) -> Self {
        var copy = Self(
            key: key,
            module: module,
            kind: kind,
            name: name,
            accessorKind: accessorKind,
            file: file,
            range: range,
            strippedLines: strippedLines,
            bodyLines: bodyLines,
            parameterCount: parameterCount,
            isDocumented: isDocumented,
            isAsync: isAsync,
            bodyHash: bodyHash,
            parentKey: parentKey,
            ifConfig: ifConfig,
            role: role,
            access: access
        )
        copy.complexity = complexity
        copy.effect = effect
        copy.typePath = typePath
        copy.typeFile = typeFile
        return copy
    }
}
