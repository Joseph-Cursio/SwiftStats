//
//  Toolchain.swift
//  SwiftStatsCore
//
//  The toolchain a snapshot was taken with (PRD §6.2).
//

/// The Swift toolchain and SDK in use during a scan.
public struct Toolchain: Codable, Hashable, Sendable {
    /// The first line of `swift --version` in the package directory.
    public let swiftVersion: String?
    /// `swiftly use`'s selection and its source, when swiftly is installed.
    public let swiftlySelection: String?
    /// `xcrun --show-sdk-version`.
    public let sdkVersion: String?

    /// Creates a toolchain description. Fields are documented on their properties.
    public init(swiftVersion: String?, swiftlySelection: String?, sdkVersion: String?) {
        self.swiftVersion = swiftVersion
        self.swiftlySelection = swiftlySelection
        self.sdkVersion = sdkVersion
    }
}
