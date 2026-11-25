//
//  RetainedModulesTests.swift
//  SwiftStatsCoreTests
//
//  Which targets' public declarations outskirts retains (M7, design §5.2,
//  review C14): the targets library products list and the package targets
//  they re-export with `@_exported import`, transitively, each with a kept
//  or variant unit; and the modules a file re-exports, read from its
//  syntax. From source text and hand-made describes, no fixture or tool.
//

import SwiftParser
@testable import SwiftStatsCore
import Testing

/// The retained targets and the modules a file re-exports.
@Suite("Retained modules")
struct RetainedModulesTests {
    /// A library target named `name`.
    private static func target(_ name: String, type: String = "library") -> DescribedTarget {
        DescribedTarget(name: name, type: type, moduleType: "SwiftTarget", path: "Sources/\(name)", sources: [])
    }

    @Test("""
        a file re-exports the first path component of each @_exported import, at the top level or in any #if \
        clause, with an access level or the attribute on a line of its own, backticks dropped; plain and \
        @testable imports re-export nothing
        """)
    func exportedImports() {
        let source = """
            import Foundation
            @testable import Tested
            @_exported import CoreBase
            @_exported import struct Shapes.Circle
            @_exported import `Escaped`
            #if canImport(Linux)
            @_exported import LinuxOnly
            #else
            @_exported @preconcurrency import Elsewhere
            #endif
            @_exported public import Modern
            @_exported package import Shared
            @_exported
            import NextLine
            func make() {}
            """
        #expect(ExportedImports.modules(in: Parser.parse(source: source)) == [
            "CoreBase", "Shapes", "Escaped", "LinuxOnly", "Elsewhere", "Modern", "Shared", "NextLine"
        ])
        #expect(ExportedImports.modules(in: Parser.parse(source: "import CoreBase\n")).isEmpty)
    }

    @Test("""
        the retained targets are the library products' targets and the package targets they re-export, by C99 \
        module name and transitively, each with a kept or variant unit; a re-export by a target no library \
        re-exports, or of a module the package doesn't declare, retains nothing
        """)
    func retainedTargets() {
        let package = DescribedPackage(
            name: "Package",
            targets: [
                Self.target("Umbrella"), Self.target("core-base"), Self.target("Deep"), Self.target("Unbuilt"),
                Self.target("Loose"), Self.target("Hidden"), Self.target("App", type: "executable"),
                Self.target("Kit")
            ],
            products: [
                DescribedProduct(name: "Umbrella", kind: "library", targets: ["Umbrella"]),
                DescribedProduct(name: "Kit", kind: "library", targets: ["Kit"]),
                DescribedProduct(name: "App", kind: "executable", targets: ["App"])
            ]
        )
        let exports: [String: Set<String>] = [
            "Umbrella": ["core_base", "Foundation", "Unbuilt"],
            "core-base": ["Deep"],
            "Loose": ["Hidden"],
            "App": ["Hidden"]
        ]
        let read: Set<String> = ["Umbrella", "core-base", "Deep", "Loose", "Hidden", "App", "Kit"]

        #expect(IndexAdapter.libraryModules(package, reading: read, exports: exports) == [
            "Deep", "Kit", "Umbrella", "core-base"
        ])
        #expect(IndexAdapter.libraryModules(package, reading: read, exports: [:]) == ["Kit", "Umbrella"])
    }

    @Test("the option names the retained targets, or none, then the rule that chose them")
    func option() {
        #expect(PeripheryCommand.retainOption(targets: ["index-kit", "IndexCore"])
            == "retain-public-modules: IndexCore, index-kit (the targets library products list and the package "
            + "targets they re-export with @_exported import, transitively, each with a kept or variant unit)")
        #expect(PeripheryCommand.retainOption(targets: []).hasPrefix("retain-public-modules: none (the targets"))
    }
}
