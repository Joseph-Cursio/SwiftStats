//
//  PackageFileClass.swift
//  SwiftStatsCore
//
//  What a tool's mapping does with one of the files it names (M5, M6):
//  coverage sorts the export's files into these classes, mutation the
//  files its mutants are in.
//

/// Where a file a tool names belongs.
enum PackageFileClass: Equatable {
    /// Under the coverage build directory or a `.build` directory.
    case build
    /// A production file the scan parsed, at this root-relative path in
    /// this module: what the tool gives for it is mapped.
    case kept(path: String, module: String)
    /// Not a Swift file, outside test targets (a C, C++ or assembly
    /// target's source or header): no record can hold what the tool gives
    /// for it.
    case otherLanguage
    /// A Swift file under the root but in no target's directory.
    case otherPackage
    /// Outside the package root.
    case outsideRoot
    /// In a test target's directory.
    case testFile
    /// A production file the scan didn't parse, at this root-relative path
    /// in this module: what the tool gives for it is listed, for `reason`.
    case unmapped(path: String, module: String, reason: String)
}
