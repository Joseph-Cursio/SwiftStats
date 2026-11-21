//
//  RiskSubject.swift
//  SwiftStatsCore
//
//  What a risk marker is about (M5): the function, type or file a finding
//  location attaches it to, as risky + untested lists it.
//

/// A function, type or file holding risk markers.
struct RiskSubject: Hashable {
    /// `function`, `type` or `file`.
    let target: FindingTarget
    /// The function's key, the type's owner (`<module>::<type path>`, with
    /// ` @ <file>` when file-scoped), or the file's path.
    let name: String
}
