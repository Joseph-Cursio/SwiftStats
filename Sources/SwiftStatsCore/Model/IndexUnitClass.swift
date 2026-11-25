//
//  IndexUnitClass.swift
//  SwiftStatsCore
//
//  The class `UnitFilter` gives each unit of the T1 build's index store
//  (M7, design §2.3), the first that applies in this order: an SDK
//  interface's (`system`), another package's, a generated file's or one
//  with no main file (`otherPackage`), a package file's for a module no
//  target has (`otherModule`), a unit whose main file is gone or has left
//  its module's target (`stale`), an older unit of the same module, file
//  and triple (`duplicate`), a unit with a sibling of another triple
//  (`variant`), and a current compile of a package file (`kept`). The
//  scan lists the units of the last five classes and counts every class,
//  writing each class as its raw value (`IndexUnitRow`).
//

/// A unit's class in the T1 build's index store.
public enum IndexUnitClass: String, CaseIterable, Sendable {
    /// An older unit of the same module, main file and triple.
    case duplicate
    /// A current compile of a package file.
    case kept
    /// A package file's unit for a module that is no target's.
    case otherModule
    /// A unit of no package file: another package's, a generated file's,
    /// or one with no main file.
    case otherPackage
    /// A unit whose main file is gone or has left its module's target.
    case stale
    /// A system unit.
    case system
    /// A kept unit with a sibling of another triple.
    case variant

    /// Whether the walk reads the unit's records.
    var isRead: Bool {
        self == .kept || self == .variant
    }

    /// Whether the quarantine moves the unit out of the store (when its
    /// main file is under the package root).
    var isQuarantined: Bool {
        self == .stale || self == .otherModule
    }

    /// Whether the scan lists the unit by name: every class but `system`
    /// and `otherPackage`, whose units aren't the package's compiles.
    var isListed: Bool {
        self != .system && self != .otherPackage
    }
}
