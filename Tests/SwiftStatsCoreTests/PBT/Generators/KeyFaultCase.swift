//
//  KeyFaultCase.swift
//  SwiftStatsCoreTests
//
//  One input of P11.3: a valid configuration with a key fault put in,
//  laid out as text, and the fault, which says what reading it gives.
//

import Testing

/// A configuration holding unknown or repeated keys.
struct KeyFaultCase: Sendable, CustomTestStringConvertible {
    /// The valid configuration's members, before the fault.
    let members: [YAMLDraft.Member]
    /// The fault put in.
    let fault: KeyFault
    /// How the text is laid out.
    let layout: ConfigLayout

    /// The configuration's text, fault included.
    var text: String {
        layout.text(of: fault.applied(to: members))
    }

    /// The text as a Swift literal and the fault, in ASCII, so a
    /// failure's seed reaches the console.
    var testDescription: String {
        PBTTrace.ascii("YAML \(text.debugDescription) with \(fault)")
    }
}
