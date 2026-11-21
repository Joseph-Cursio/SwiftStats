//
//  TypePathMatch.swift
//  SwiftStatsCore
//
//  Whether a test names a type (M5, tests per public function): by its
//  simple name, unqualified, or qualified by names that end the path a
//  type's member records give its parents, which may start with its module
//  (`Mod.Outer.Inner`, `Outer.Inner` and `Inner` all name `Outer.Inner` in
//  `Mod`; `Other.Inner` doesn't). The module is written by its module name,
//  the target's C99 name (`my_lib` for the target `my-lib`). Names are
//  compared without backticks.
//

/// Matches the type paths tests write against records' types.
enum TypePathMatch {
    /// The qualifiers that may stand before the simple name of the type at
    /// `path` in the target `module`: the module name, then the path's
    /// other components.
    static func allowedQualifiers(module: String, path: String) -> [String] {
        [CoverageBundles.moduleName(of: module)] + components(of: path).dropLast()
    }

    /// `path`'s components, without backticks.
    static func components(of path: String) -> [String] {
        path.split(separator: ".").map { TestReferences.unescaped(String($0)) }
    }

    /// Whether `written` ends `allowed`; an empty one always does.
    static func isSuffix(_ written: [String], of allowed: [String]) -> Bool {
        written.count <= allowed.count && Array(allowed.suffix(written.count)) == written
    }
}
