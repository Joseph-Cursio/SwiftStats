//
//  IndexUnitCounts.swift
//  SwiftStatsCore
//
//  How many units of the T1 build's index store each class holds (M7,
//  design §2.3), and how many the quarantine moved out of the store.
//

/// The index store's units counted by class.
public struct IndexUnitCounts: Codable, Hashable, Sendable {
    /// SDK interface units.
    public let system: Int
    /// Units of no package file.
    public let otherPackage: Int
    /// Package files' units for modules no target has.
    public let otherModule: Int
    /// Units whose main file is gone or has left its target.
    public let stale: Int
    /// Older units of one module, file and triple.
    public let duplicate: Int
    /// Units read with a sibling of another triple.
    public let variant: Int
    /// Current compiles of package files.
    public let kept: Int
    /// Stale and other-module units moved out of the store.
    public let quarantined: Int

    /// The counts of `classes`, each unit's class, with `quarantined`
    /// units moved out.
    init(_ classes: [IndexUnitClass], quarantined: Int) {
        system = classes.count { $0 == .system }
        otherPackage = classes.count { $0 == .otherPackage }
        otherModule = classes.count { $0 == .otherModule }
        stale = classes.count { $0 == .stale }
        duplicate = classes.count { $0 == .duplicate }
        variant = classes.count { $0 == .variant }
        kept = classes.count { $0 == .kept }
        self.quarantined = quarantined
    }

    /// The counts given, as the store reads them back. Fields are
    /// documented on their properties.
    init(
        system: Int,
        otherPackage: Int,
        otherModule: Int,
        stale: Int,
        duplicate: Int,
        variant: Int,
        kept: Int,
        quarantined: Int
    ) {
        self.system = system
        self.otherPackage = otherPackage
        self.otherModule = otherModule
        self.stale = stale
        self.duplicate = duplicate
        self.variant = variant
        self.kept = kept
        self.quarantined = quarantined
    }
}
