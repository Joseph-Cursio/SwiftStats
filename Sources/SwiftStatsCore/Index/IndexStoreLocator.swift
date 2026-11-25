//
//  IndexStoreLocator.swift
//  SwiftStatsCore
//
//  Where the `index` collector finds what it reads (M7, design §1.3 steps
//  1 and 10, §2.4): the index store the T1 build wrote, `<scratch>/out`,
//  which must hold `v5/units` (every build passes `--build-system
//  swiftbuild`, so the native layout never occurs), and the build
//  toolchain's own `libIndexStore.dylib`, beside its runtime resources in
//  `<toolchain>/usr/lib` (`xcrun --find` can't find it, so there is no
//  fallback). Either one missing fails the collector; the reason names
//  the build directory and the toolchain by their placeholders.
//

import Foundation

/// Finds the index store and the libIndexStore.dylib to read it with.
enum IndexStoreLocator {
    /// Why the store or the library isn't there.
    struct Failure: Error, CustomStringConvertible {
        /// What is missing, for the `index` collector's reason.
        let description: String
    }

    /// An index store and the library to read it with.
    struct Location: Hashable, Sendable {
        /// The store: the directory holding `v5`.
        let store: URL
        /// The toolchain's `libIndexStore.dylib`.
        let library: URL
    }

    /// The store and library of the build that left `products`, with its
    /// build directory written `<build>` and its toolchain `<toolchain>`
    /// in a failure.
    static func locate(_ products: BuildSession.Products) throws -> Location {
        try locate(
            store: products.store,
            library: products.toolchain.libIndexStore,
            redacting: [
                (products.scratch, CoverageCommand.buildPlaceholder),
                (products.toolchain.directory, CoverageCommand.toolchainPlaceholder)
            ]
        )
    }

    /// The store at `store` and the library at `library`, when the library
    /// is a file and the store holds `v5/units`; otherwise a failure
    /// naming what is missing, each directory in `replacements` written as
    /// its placeholder.
    static func locate(store: URL, library: URL, redacting replacements: [(URL, String)]) throws -> Location {
        guard isEntry(library, directory: false) else {
            let folder = library.deletingLastPathComponent().path
            throw failure("the toolchain has no libIndexStore.dylib (\(folder))", replacements)
        }
        guard isEntry(store.appendingPathComponent(BuildSession.unitsPath), directory: true) else {
            throw failure("the build wrote no index store at \(store.path)", replacements)
        }
        return Location(store: store, library: library)
    }

    /// Whether `url` names an existing directory when `directory`, or an
    /// existing entry that isn't one otherwise.
    private static func isEntry(_ url: URL, directory: Bool) -> Bool {
        var isDirectory: ObjCBool = false
        return FileManager.default.fileExists(atPath: url.path, isDirectory: &isDirectory)
            && isDirectory.boolValue == directory
    }

    /// A failure saying `text`, its directories in `replacements` redacted.
    private static func failure(_ text: String, _ replacements: [(URL, String)]) -> Failure {
        Failure(description: SwiftInferTargetRun.redacted(text, replacing: replacements))
    }
}
