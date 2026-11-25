//
//  PeripheryUnits.swift
//  SwiftStatsCore
//
//  What outskirts' runs need from the index store before they start (M7,
//  design §2.3, §2.4, §5.2, §5.3): stale and other-module units moved out
//  of the store (outskirts would otherwise keep a moved file's old-module
//  unit), the library-product targets and the package targets they
//  re-export (`@_exported import`, transitively) with a kept or variant
//  unit, whose public declarations are retained, and, when the `index`
//  collector ran, the USRs it read as local. When the `index` collector
//  ran, it has already moved the units and gives both; when it was
//  disabled or failed, only the unit headers are read, through the same
//  source, and classed here, the retained targets found as the index
//  finds them, and local variables are told by their place alone. The
//  units are moved here only when the index didn't get as far as its own
//  quarantine: one that failed after it has already moved them, and a
//  second move would empty the quarantine folder of what it moved.
//

import Foundation

/// The units' part of an outskirts run.
struct PeripheryUnits: Sendable {
    /// The library-product targets and the package targets they
    /// re-export, transitively, with a kept or variant unit, in code point
    /// order.
    let retained: [String]
    /// The USRs the index read as local; empty when it didn't run.
    let localUSRs: Set<String>

    /// What `index`, which ran with `report`, gives.
    init(index report: IndexReport, localUSRs: Set<String>) {
        retained = report.libraryModules
        self.localUSRs = localUSRs
    }

    /// The units of the store the build that left `products` wrote, for
    /// the package at `root`, read without the `index` collector's
    /// results: the store located and opened by `factory`, every unit
    /// header read and classed, and, when `moving`, the stale and
    /// other-module units under the root moved out; `exports` the modules
    /// each target's parsed files re-export, by target name.
    init(
        products: BuildSession.Products,
        root: URL,
        opening factory: (_ store: URL, _ library: URL) throws -> any IndexStoreSource,
        moving: Bool,
        exports: [String: Set<String>]
    ) throws {
        let location = try IndexStoreLocator.locate(products)
        let source = try factory(location.store, location.library)
        let filter = try UnitFilter(
            root: IndexStoreReader.realPath(root.path),
            scratch: products.scratch.path,
            package: products.package
        )
        let classed = filter.classify(try IndexWalk.units(of: source))
        if moving {
            _ = try filter.quarantine(classed)
        }
        let read = Set(classed.filter(\.unitClass.isRead).compactMap { filter.target(of: $0.unit.module) })
        retained = IndexAdapter.libraryModules(products.package, reading: read, exports: exports)
        localUSRs = []
    }

    /// The units' part of `job`: what its `index` collector gives when it
    /// ran, else the units read here, moved only when the index didn't
    /// get as far as its own quarantine.
    static func of(_ job: PeripheryJob) throws -> Self {
        if let report = job.index.report {
            return Self(index: report, localUSRs: job.index.localUSRs)
        }
        return try Self(
            products: job.products,
            root: job.scan.root,
            opening: job.opening,
            moving: job.index.quarantineRan == false,
            exports: job.scan.exportedImports
        )
    }
}
