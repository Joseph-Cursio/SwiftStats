//
//  GlobCase.swift
//  SwiftStatsCoreTests
//
//  One input of the glob properties: a glob, written as the atoms of its
//  core with an optional leading `./` and trailing `/`s, and a path to
//  match it against. The core neither starts with `./`, nor ends in `/`,
//  nor is `.` (`GlobGen` makes sure), so dropping one leading `./` and every
//  trailing `/` from the glob, as PRD §10.1 says a glob is read, gives
//  the core back.
//

import Testing

/// A glob, as its core and decoration, and a path.
struct GlobCase: Sendable, CustomTestStringConvertible {
    /// The prefix a glob may start with, meaning the package root.
    static let rootPrefix = "./"

    /// The pieces the core is written as, in order.
    let atoms: [String]
    /// Whether the glob starts with `./`.
    let hasRootPrefix: Bool
    /// How many `/`s end the glob.
    let trailingSlashes: Int
    /// The path the glob is matched against.
    let path: String
    /// The index of the atom the path fills by an edge fill, every other
    /// atom canonically, or nil.
    let edgeAtom: Int?
    /// That atom's edge fill, or nothing.
    let edgeFill: String

    /// The glob without its decoration: its atoms, joined.
    var core: String {
        atoms.joined()
    }

    /// The glob as written: the core, `./` before it when it has the
    /// prefix, and its trailing `/`s.
    var glob: String {
        (hasRootPrefix ? Self.rootPrefix : "") + core + String(repeating: "/", count: trailingSlashes)
    }

    /// The glob and the path as Swift literals, in ASCII (`PBTTrace.ascii`),
    /// so a failure's seed reaches the console.
    var testDescription: String {
        let edge = edgeAtom.map { ", atom \($0) filled as \(edgeFill.debugDescription)" } ?? ""
        return PBTTrace.ascii(
            "glob \(glob.debugDescription) (core \(core.debugDescription)) against \(path.debugDescription)" + edge
        )
    }
}
