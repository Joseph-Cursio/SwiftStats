//
//  CoverageFileClass.swift
//  SwiftStatsCore
//
//  What the coverage mapping does with one of the export's files (M5).
//

/// Where an export file belongs.
enum CoverageFileClass: Equatable {
    /// Under the coverage build directory or a `.build` directory.
    case build
    /// A production file the scan parsed, at this root-relative path in
    /// this module: its entries are mapped.
    case kept(path: String, module: String)
    /// Not a Swift file, outside test targets (a C, C++ or assembly
    /// target's source or header): no record can hold its entries.
    case otherLanguage
    /// A Swift file under the root but in no target's directory.
    case otherPackage
    /// Outside the package root.
    case outsideRoot
    /// In a test target's directory.
    case testFile
    /// A production file the scan didn't parse, at this root-relative path
    /// in this module: its entries are listed, for `reason`.
    case unmapped(path: String, module: String, reason: String)
}
