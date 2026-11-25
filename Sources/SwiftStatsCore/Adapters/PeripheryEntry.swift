//
//  PeripheryEntry.swift
//  SwiftStatsCore
//
//  One entry of an outskirts run's JSON (M7, design §5.3), as SwiftStats
//  reads it: its run and 1-based place in that run's output, its one hint
//  (split as `name(text)` into the name and the text, as
//  `redundantConformance(replace with: …)` carries one), the declaration's
//  kind, name, accessibility, attributes and modifiers, its ids (`s:` and
//  `c:` USRs, or outskirts' synthetic `param-…` and `import-…` ids), its
//  modules by target name where they are the package's (C99 names
//  otherwise), its location (the real path, NFC; the path in the package
//  when under the root; the 1-based line and UTF-8 column of the name)
//  and its class.
//

/// An outskirts result.
struct PeripheryEntry: Hashable, Sendable {
    /// The run that reported it.
    let run: PeripheryCommand.Run
    /// Its 1-based place in that run's output.
    let ordinal: Int
    /// Its hint's name, such as `unused`.
    let hint: String
    /// The text in the hint's parentheses; nil when it has none.
    let hintText: String?
    /// The declaration's kind, such as `function.free` or `var.global`.
    let kind: String
    /// The declaration's name.
    let name: String
    /// Its accessibility, as outskirts writes it.
    let accessibility: String
    /// Its attributes.
    let attributes: [String]
    /// Its modifiers.
    let modifiers: [String]
    /// Its ids.
    let ids: [String]
    /// Its modules: target names for the package's, else C99 names.
    let modules: [String]
    /// The real path of its file, NFC.
    let path: String
    /// Its file's path in the package; nil outside the root.
    let file: String?
    /// The 1-based line of its name.
    let line: Int
    /// The 1-based UTF-8 column of its name.
    let column: Int
    /// Its class.
    let entryClass: PeripheryEntryClass

    /// The same entry of class `entryClass`.
    func classed(_ entryClass: PeripheryEntryClass) -> Self {
        Self(
            run: run,
            ordinal: ordinal,
            hint: hint,
            hintText: hintText,
            kind: kind,
            name: name,
            accessibility: accessibility,
            attributes: attributes,
            modifiers: modifiers,
            ids: ids,
            modules: modules,
            path: path,
            file: file,
            line: line,
            column: column,
            entryClass: entryClass
        )
    }
}
