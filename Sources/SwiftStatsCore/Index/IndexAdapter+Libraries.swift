//
//  IndexAdapter+Libraries.swift
//  SwiftStatsCore
//
//  The targets whose public declarations outskirts retains (M7, design
//  §5.2 as built, review C14), which `indexScan.libraryModules` stores and
//  test-only production code's public-API exclusion reads: the targets
//  library products list and the package targets they re-export with
//  `@_exported import`, transitively, each with a kept or variant unit.
//

extension IndexAdapter {
    /// The library-product targets of `package`, and the package targets
    /// they re-export by `exports` (the modules each target's parsed files
    /// re-export, by target name), transitively, among `read`, the targets
    /// with a kept or variant unit, in code point order: the modules whose
    /// public declarations outskirts retains (design §5.2; a re-exported
    /// target's public declarations are the product's API too, review C14).
    static func libraryModules(
        _ package: DescribedPackage,
        reading read: Set<String>,
        exports: [String: Set<String>]
    ) -> [String] {
        let targetOfModule = Dictionary(package.targets.map { ($0.c99name, $0.name) }) { first, _ in first }
        var retained = Set(package.products.filter { $0.kind == libraryKind }.flatMap(\.targets))
        var pending = Array(retained)
        while let target = pending.popLast() {
            for module in exports[target, default: []] {
                if let exported = targetOfModule[module], retained.insert(exported).inserted {
                    pending.append(exported)
                }
            }
        }
        return retained.intersection(read).sorted(by: CodePointOrder.precedes)
    }
}
