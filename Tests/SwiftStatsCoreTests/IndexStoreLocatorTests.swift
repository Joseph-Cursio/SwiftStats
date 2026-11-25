//
//  IndexStoreLocatorTests.swift
//  SwiftStatsCoreTests
//
//  `IndexStoreLocator` (M7, design §1.3, §2.4): the store and library are
//  found when there, and each missing one fails with its text, the build
//  directory and the toolchain written as placeholders; also through the
//  products a fake T1 build leaves. Nothing is loaded or read.
//

import Foundation
@testable import SwiftStatsCore
import Testing

/// Finding the index store and the libIndexStore.dylib.
@Suite("Index store locator")
struct IndexStoreLocatorTests {
    /// A temporary toolchain and build directory, as a T1 build leaves them.
    private struct Layout {
        /// The folder holding both.
        let top: URL

        /// The toolchain, holding `usr/lib`.
        var toolchain: URL {
            top.appendingPathComponent("toolchain")
        }

        /// The toolchain's `libIndexStore.dylib`.
        var library: URL {
            toolchain.appendingPathComponent("usr/lib/libIndexStore.dylib")
        }

        /// The build directory.
        var build: URL {
            top.appendingPathComponent("index-build")
        }

        /// The index store, `<build>/out`.
        var store: URL {
            build.appendingPathComponent("out")
        }

        /// The placeholders a failure uses.
        var replacements: [(URL, String)] {
            [(build, "<build>"), (toolchain, "<toolchain>")]
        }

        /// A layout in a fresh temporary folder, with the toolchain's
        /// `usr/lib` and the build directory made.
        static func make() throws -> Self {
            let layout = Self(top: FileManager.default.temporaryDirectory
                .appendingPathComponent("IndexStoreLocator-\(UUID().uuidString)"))
            try FileManager.default.createDirectory(
                at: layout.library.deletingLastPathComponent(),
                withIntermediateDirectories: true
            )
            try FileManager.default.createDirectory(at: layout.build, withIntermediateDirectories: true)
            return layout
        }

        /// Makes the library an empty file and the store's `v5/units`.
        func populate() throws {
            try Data().write(to: library)
            try FileManager.default.createDirectory(
                at: store.appendingPathComponent("v5/units"),
                withIntermediateDirectories: true
            )
        }

        /// What the locator says of this layout's store and library.
        func locate() throws -> IndexStoreLocator.Location {
            try IndexStoreLocator.locate(store: store, library: library, redacting: replacements)
        }

        /// Removes the layout.
        func remove() {
            try? FileManager.default.removeItem(at: top)
        }
    }

    /// The failure text `locate` throws.
    private static func failure(of locate: () throws -> IndexStoreLocator.Location) -> String? {
        do {
            _ = try locate()
            return nil
        } catch {
            return (error as? IndexStoreLocator.Failure)?.description
        }
    }

    @Test("a library file and a store holding v5/units are located as given")
    func located() throws {
        let layout = try Layout.make()
        defer { layout.remove() }
        try layout.populate()

        #expect(try layout.locate() == IndexStoreLocator.Location(store: layout.store, library: layout.library))
    }

    @Test("a toolchain with no libIndexStore.dylib, or a folder in its place, fails naming <toolchain>/usr/lib")
    func noLibrary() throws {
        let layout = try Layout.make()
        defer { layout.remove() }
        try layout.populate()
        try FileManager.default.removeItem(at: layout.library)
        let expected = "the toolchain has no libIndexStore.dylib (<toolchain>/usr/lib)"

        #expect(Self.failure { try layout.locate() } == expected)
        try FileManager.default.createDirectory(at: layout.library, withIntermediateDirectories: false)
        #expect(Self.failure { try layout.locate() } == expected)
    }

    @Test("a build directory with no out, or an out with no v5/units, fails naming <build>/out")
    func noStore() throws {
        let layout = try Layout.make()
        defer { layout.remove() }
        try Data().write(to: layout.library)
        let expected = "the build wrote no index store at <build>/out"

        #expect(Self.failure { try layout.locate() } == expected)
        try FileManager.default.createDirectory(
            at: layout.store.appendingPathComponent("v5"),
            withIntermediateDirectories: true
        )
        #expect(Self.failure { try layout.locate() } == expected)
        try Data().write(to: layout.store.appendingPathComponent("v5/units"))
        #expect(Self.failure { try layout.locate() } == expected)
    }

    @Test("the library is looked for before the store")
    func libraryFirst() throws {
        let layout = try Layout.make()
        defer { layout.remove() }

        let expected = "the toolchain has no libIndexStore.dylib (<toolchain>/usr/lib)"

        #expect(Self.failure { try layout.locate() } == expected)
    }

    @Test("""
        a fake build's products are located once the toolchain has its library, and fail with the \
        placeholders before
        """)
    func products() throws {
        try BuildHarness.run(try FakeToolchain.recordedBuild()) { outcome in
            let products = try #require(outcome.run.products)

            #expect(Self.failure { try IndexStoreLocator.locate(products) }
                == "the toolchain has no libIndexStore.dylib (<toolchain>/usr/lib)")
            #expect(products.toolchain.libIndexStore.path
                == outcome.toolchain.directory.appendingPathComponent("usr/lib/libIndexStore.dylib").path)
            try Data().write(to: products.toolchain.libIndexStore)
            let location = try IndexStoreLocator.locate(products)
            #expect(location.store.path == outcome.build.appendingPathComponent("out").path)
            #expect(location.library.path == products.toolchain.libIndexStore.path)
        }
    }

    @Test("a fake build that wrote no store fails as the build's own store check does")
    func productsWithoutStore() throws {
        var scenario = try FakeToolchain.recordedBuild()
        scenario.makesStore = false
        try BuildHarness.run(scenario) { outcome in
            let products = try #require(outcome.run.products)
            try Data().write(to: products.toolchain.libIndexStore)

            #expect(Self.failure { try IndexStoreLocator.locate(products) } == products.storeFailure)
            #expect(products.storeFailure == "the build wrote no index store at <build>/out")
        }
    }
}
