import Foundation
@testable import SwiftStatsCore
import Testing

/// The warning for a `.swiftinfer/` join file that is present but can't be
/// read (PRD §7.11): it names the file relatively and gives a reason with
/// no path or address, so scans of one tree warn alike.
@Suite("Property join warnings")
struct PropertyJoinWarningTests {
    @Test("""
        a join file that can't be read warns with a reason holding no path or address, alike on every scan, \
        and a directory counts as one that can't be read
        """)
    func unreadableWarningsAreStable() throws {
        let root = try SnapshotHarness.temporaryDirectory("Joins")
        defer { try? FileManager.default.removeItem(at: root) }
        let settings = root.appendingPathComponent(PropertyJoins.directory)
        try FileManager.default.createDirectory(
            at: settings.appendingPathComponent(PropertyJoins.decisionsFile),
            withIntermediateDirectories: true
        )
        try Data("{".utf8).write(to: settings.appendingPathComponent(PropertyJoins.interactionDecisionsFile))
        let evidenceFile = settings.appendingPathComponent(PropertyJoins.verifyEvidenceFile)
        try Data("{\"records\": []}".utf8).write(to: evidenceFile)
        try FileManager.default.setAttributes([.posixPermissions: 0], ofItemAtPath: evidenceFile.path)
        defer { try? FileManager.default.setAttributes([.posixPermissions: 0o644], ofItemAtPath: evidenceFile.path) }
        // Root reads a file whatever its permissions.
        let deniesReading = getuid() != 0

        let first = PropertyJoins(root: root).warnings
        let second = PropertyJoins(root: root).warnings

        #expect(first == second)
        #expect(first.map(\.file) == [".swiftinfer/decisions.json", ".swiftinfer/interaction-decisions.json"]
            + (deniesReading ? [".swiftinfer/verify-evidence.json"] : []))
        let prefix = "not readable, so SwiftInferProperties' suggestions aren't joined to it: "
        #expect(first.first?.message == prefix + "Is a directory")
        if deniesReading {
            #expect(first.last?.message == prefix + "Permission denied")
        }
        let resolved = root.resolvingSymlinksInPath().path
        for warning in first {
            #expect(warning.message.hasPrefix(prefix))
            for leak in [root.path, resolved, "NSFilePath", "NSURL", "0x"] {
                #expect(warning.message.contains(leak) == false, "\(leak)")
            }
        }
    }
}
