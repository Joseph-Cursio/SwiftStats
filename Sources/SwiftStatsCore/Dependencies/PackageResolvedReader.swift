//
//  PackageResolvedReader.swift
//  SwiftStatsCore
//
//  Reads `Package.resolved` (PRD §7.14), versions 1 to 3.
//

import Foundation

/// Reads the pins in `Package.resolved`.
enum PackageResolvedReader {
    /// A pin's state.
    private struct State: Decodable {
        let version: String?
        let branch: String?
        let revision: String?
    }

    /// A version 2 or 3 pin.
    private struct Pin: Decodable {
        let identity: String
        let location: String
        let state: State
    }

    /// A version 1 pin, which names the package and its URL.
    private struct LegacyPin: Decodable {
        let repositoryURL: String
        let state: State
    }

    /// Versions 2 and 3: the pins at the top level.
    private struct CurrentFile: Decodable {
        let pins: [Pin]
    }

    /// Version 1: the pins inside `object`.
    private struct LegacyFile: Decodable {
        let object: LegacyObject
    }

    /// Version 1's `object`.
    private struct LegacyObject: Decodable {
        let pins: [LegacyPin]
    }

    /// The pins in `root/Package.resolved`; nil when there is no such
    /// file, and a warning when it can't be read.
    static func lockfile(root: URL) -> (lockfile: Lockfile?, warning: ScanWarning?) {
        let file = root.appendingPathComponent("Package.resolved")
        guard let data = try? Data(contentsOf: file) else {
            return (nil, nil)
        }
        do {
            return (Lockfile(pins: try pins(in: data)), nil)
        } catch {
            return (nil, ScanWarning(file: "Package.resolved", message: "not readable: \(error)"))
        }
    }

    /// The pins in a `Package.resolved` file's `data`, sorted by identity.
    static func pins(in data: Data) throws -> [DependencyPin] {
        let decoder = JSONDecoder()
        if let legacy = try? decoder.decode(LegacyFile.self, from: data) {
            return legacy.object.pins.map { pin in
                DependencyPin(
                    identity: identity(of: pin.repositoryURL),
                    location: pin.repositoryURL,
                    version: pin.state.version,
                    branch: pin.state.branch,
                    revision: pin.state.revision
                )
            }
            .sorted { $0.identity < $1.identity }
        }
        let current = try decoder.decode(CurrentFile.self, from: data)
        return current.pins.map { pin in
            DependencyPin(
                identity: pin.identity,
                location: pin.location,
                version: pin.state.version,
                branch: pin.state.branch,
                revision: pin.state.revision
            )
        }
        .sorted { $0.identity < $1.identity }
    }

    /// SwiftPM's identity for a URL: its last component, lowercased, without `.git`.
    static func identity(of url: String) -> String {
        var name = url.split(separator: "/").last.map(String.init) ?? url
        if name.hasSuffix(".git") {
            name.removeLast(".git".count)
        }
        return name.lowercased()
    }
}
