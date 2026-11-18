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
            parameterCount: parameterCount,
            isDocumented: isDocumented,
            bodyHash: bodyHash,
            parentKey: parentKey,
            ifConfig: ifConfig,
            role: role
        )
        copy.complexity = complexity
        return copy
    }
}
