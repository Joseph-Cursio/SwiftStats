//
//  ConfigCase.swift
//  SwiftStatsCoreTests
//
//  One input of P11.1: a valid configuration, perhaps with one flaw put
//  in, laid out as text; or text that isn't a configuration at all.
//

import Testing

/// A configuration's text, and how it was made.
struct ConfigCase: Sendable, CustomTestStringConvertible {
    /// The valid configuration's members, before any flaw.
    let members: [YAMLDraft.Member]
    /// The flaw put in, or nil.
    let flaw: ConfigFlaw?
    /// Text that isn't a configuration, which replaces the members, or nil.
    let soup: String?
    /// How the members are laid out.
    let layout: ConfigLayout

    /// Whether the text is the valid configuration, unflawed.
    var isValid: Bool {
        flaw == nil && soup == nil
    }

    /// The text read.
    var text: String {
        soup ?? layout.text(of: flaw.map { $0.applied(to: members) } ?? members)
    }

    /// The text as a Swift literal, and its flaw, in ASCII, so a
    /// failure's seed reaches the console.
    var testDescription: String {
        let made = soup != nil ? "not a configuration" : flaw.map { "flaw: \($0)" } ?? "valid"
        return PBTTrace.ascii("YAML \(text.debugDescription) (\(made))")
    }
}
