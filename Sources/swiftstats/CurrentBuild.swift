//
//  CurrentBuild.swift
//  swiftstats
//
//  This executable's build identity (PRD §6.2): the build-input hash that
//  BuildInfoPlugin embedded, or, when the build had no git, the SHA-256 of
//  the executable itself.
//

import CryptoKit
import Foundation
import SwiftStatsBuildInfo
import SwiftStatsCore

/// The running build of SwiftStats.
enum CurrentBuild {
    /// How many characters of the commit the label keeps.
    private static let commitLength = 40

    /// The identity and label snapshots record.
    static var swiftStats: SwiftStatsBuild {
        let commit = SwiftStatsBuildInfo.commit
        let dirty = SwiftStatsBuildInfo.isDirty ? "+dirty" : ""
        let label = commit.isEmpty ? nil : "git:\(commit.prefix(commitLength))\(dirty)"
        if SwiftStatsBuildInfo.inputHash.isEmpty == false {
            return SwiftStatsBuild(identity: "inputs:\(SwiftStatsBuildInfo.inputHash)", label: label)
        }
        return SwiftStatsBuild(identity: "sha256:\(executableHash() ?? "unknown")", label: label)
    }

    /// The SHA-256 of this executable, or nil when it can't be read.
    private static func executableHash() -> String? {
        guard let path = Bundle.main.executablePath,
              let data = try? Data(contentsOf: URL(fileURLWithPath: path).resolvingSymlinksInPath()) else {
            return nil
        }
        return SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined()
    }
}
