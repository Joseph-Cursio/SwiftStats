import Foundation
@testable import SwiftStatsCore
import Testing

/// What the T1 group reads from `swift package describe --type json` (M7,
/// design §1.3): each product's name, kind and targets, and each target's
/// C99 module name, decoded, or computed by SwiftPM's rule when absent.
@Suite("Package description")
struct PackageDescriptionTests {
    /// A description shaped as SwiftPM 6.4 writes it, with a dashed
    /// library-product target, a library in no product, an executable, a
    /// macro and a test target, one without a `c99name`.
    private static let describe = """
    {"name": "IndexFixture", "manifest_display_name": "IndexFixture", "path": "/work/Index",
     "products": [
       {"name": "IndexCore", "targets": ["IndexCore"], "type": {"library": ["automatic"]}},
       {"name": "IndexKit", "targets": ["index-kit"], "type": {"library": ["dynamic"]}},
       {"name": "IndexApp", "targets": ["IndexApp"], "type": {"executable": null}},
       {"name": "IndexMacros", "targets": ["IndexMacrosImpl"], "type": {"macro": null}}
     ],
     "targets": [
       {"c99name": "IndexCore", "module_type": "SwiftTarget", "name": "IndexCore", "path": "Sources/IndexCore",
        "product_memberships": ["IndexCore"], "sources": ["Core.swift"], "type": "library"},
       {"c99name": "index_kit", "module_type": "SwiftTarget", "name": "index-kit", "path": "Sources/index-kit",
        "product_memberships": ["IndexKit"], "sources": ["Kit.swift"], "type": "library"},
       {"module_type": "SwiftTarget", "name": "index-support", "path": "Sources/index-support",
        "sources": ["Support.swift"], "type": "library"},
       {"c99name": "IndexApp", "module_type": "SwiftTarget", "name": "IndexApp", "path": "Sources/IndexApp",
        "sources": ["main.swift"], "type": "executable"},
       {"c99name": "IndexCoreTests", "module_type": "SwiftTarget", "name": "IndexCoreTests",
        "path": "Tests/IndexCoreTests", "sources": ["CoreTests.swift"], "type": "test"}
     ]}
    """

    @Test("products decode with their name, kind and targets, and a description without products has none")
    func products() throws {
        let package = try JSONDecoder().decode(DescribedPackage.self, from: Data(Self.describe.utf8))
        let bare = try JSONDecoder().decode(DescribedPackage.self, from: Data(#"{"name": "A", "targets": []}"#.utf8))

        #expect(package.products == [
            DescribedProduct(name: "IndexCore", kind: "library", targets: ["IndexCore"]),
            DescribedProduct(name: "IndexKit", kind: "library", targets: ["index-kit"]),
            DescribedProduct(name: "IndexApp", kind: "executable", targets: ["IndexApp"]),
            DescribedProduct(name: "IndexMacros", kind: "macro", targets: ["IndexMacrosImpl"])
        ])
        #expect(bare.products.isEmpty)
    }

    @Test("a product type written as a string is its kind, and several keys give the first in byte order")
    func productKindShapes() throws {
        let text = """
        [{"name": "A", "targets": ["A"], "type": "plugin"},
         {"name": "B", "type": {"snippet": null, "executable": null}}]
        """
        let products = try JSONDecoder().decode([DescribedProduct].self, from: Data(text.utf8))

        #expect(products == [
            DescribedProduct(name: "A", kind: "plugin", targets: ["A"]),
            DescribedProduct(name: "B", kind: "executable", targets: [])
        ])
    }

    @Test("each target's c99name is decoded, and computed by SwiftPM's rule when the description has none")
    func decodedModuleNames() throws {
        let package = try JSONDecoder().decode(DescribedPackage.self, from: Data(Self.describe.utf8))

        #expect(package.targets.map(\.name) == [
            "IndexCore", "index-kit", "index-support", "IndexApp", "IndexCoreTests"
        ])
        #expect(package.targets.map(\.c99name) == [
            "IndexCore", "index_kit", "index_support", "IndexApp", "IndexCoreTests"
        ])
    }

    /// Each pair is what SwiftPM 6.4.2's `swift package describe` wrote as
    /// the target's `c99name`.
    @Test(
        "SwiftPM's rule turns other characters into underscores, replaces a leading digit and keeps Annex D letters",
        arguments: [
            ("my-lib", "my_lib"), ("Plain", "Plain"), ("snake_case", "snake_case"), ("a.b c", "a_b_c"),
            ("1x", "_x"), ("12ab", "_2ab"), ("9-lives", "__lives"), ("\u{0663}x", "_x"),
            ("Café", "Café"), ("\u{03A9}mega", "\u{03A9}mega"), ("\u{00B5}s", "\u{00B5}s"),
            ("\u{6570}\u{636E}", "\u{6570}\u{636E}"), ("x\u{0301}", "x_"), ("a\u{1F600}b", "a_b"), ("", "")
        ]
    )
    func computedModuleName(_ name: String, _ expected: String) {
        #expect(C99Identifier.moduleName(of: name) == expected)
    }

    @Test("a target made in code computes its c99name unless one is given")
    func madeInCode() {
        let computed = DescribedTarget(
            name: "index-kit",
            type: "library",
            moduleType: "SwiftTarget",
            path: "",
            sources: []
        )
        let given = DescribedTarget(
            name: "Odd",
            type: "library",
            moduleType: "SwiftTarget",
            path: "",
            sources: [],
            c99name: "Renamed"
        )

        #expect(computed.c99name == "index_kit")
        #expect(given.c99name == "Renamed")
    }
}
