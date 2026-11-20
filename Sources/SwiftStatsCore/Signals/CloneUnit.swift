//
//  CloneUnit.swift
//  SwiftStatsCore
//
//  What a clone copy is made of, in families (PRD §8, M4): each family it
//  covers whole, or, for a copy covering none, the family holding it. The
//  clone signals speak of copies through their units, since history and
//  matching speak in families.
//

/// One family a clone copy covers whole, or the family holding a fragment.
struct CloneUnit {
    /// The family.
    let family: FunctionFamily
    /// Its stripped lines when covered whole; the copy's own for a fragment.
    let lines: Int
    /// The first line of what the unit covers: the family's, or the fragment's.
    let start: Int
    /// The last line of what the unit covers.
    let end: Int
    /// Whether the copy covers the family whole.
    let whole: Bool

    /// What the unit pairs on across copies: its family's key without the
    /// module, types and file, such as `func visit(_: EnumDeclSyntax) -> SyntaxVisitorContinueKind`.
    var signature: String {
        let key = KeyForm.withoutFile(family.id, file: family.file)
        return key.components(separatedBy: "::").last ?? key
    }
}
