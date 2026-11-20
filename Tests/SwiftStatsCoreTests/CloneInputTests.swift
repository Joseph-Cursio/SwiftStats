import Foundation
@testable import SwiftStatsCore
import Testing

/// What SwiftCloneDetector is given and what SwiftStats accepts back (PRD
/// §7.12, §6.5): only the production files the scan read are passed, so a
/// file skipped as unreadable neither fails the collector nor enters the
/// file-list hash, and a report holding a copy whose positions aren't a
/// range fails the collector instead of stopping the scan.
@Suite("SwiftCloneDetector inputs")
struct CloneInputTests {
    /// A report of `clones`, a JSON array, as the tool writes it.
    private static func report(_ clones: String) -> String {
        """
        {"cloneCount": 0, "clones": \(clones), "duplicatedLines": 0, "fileCount": 2, "mode": "type1-2",
         "tool": "swift-clone-detector", "version": "0.1.0"}
        """
    }

    /// A fake tool whose subtree run reports `subtree` and whose other runs
    /// report no classes.
    private static func tool(subtree: String) throws -> URL {
        try FakeTool.makeCloneDetector(
            outputs: [
                "default": report(subtree),
                "--type3": report("[]"),
                "--sequence": report("[]"),
                "--type1": report("[]")
            ],
            errors: [:],
            statuses: [:]
        )
    }

    /// A package of `files`, with the library file `utf16` rewritten as UTF-16.
    private static func package(_ files: [String: String], utf16: String) throws -> TemporaryPackage {
        let package = try TemporaryPackage(files.merging([utf16: ""]) { first, _ in first })
        let data = try #require("public func wide() -> Int {\n    1\n}\n".data(using: .utf16))
        try data.write(to: package.root.appendingPathComponent(utf16))
        return package
    }

    @Test("""
        a production file the scan skips as not UTF-8 isn't given to the tool: alone, the tool isn't run \
        and the collector ran with no classes; beside a readable file, only that file is given and hashed
        """)
    func unreadableFile() throws {
        let wide = "Sources/Lib/Lib.swift"
        let readable = "Sources/Lib/B.swift"
        let test = ["Tests/LibTests/LibTests.swift": "func check() -> Int {\n    1\n}\n"]
        let alone = try Self.package(test, utf16: wide)
        defer { alone.remove() }
        let besideFiles = test.merging([readable: "func two() -> Int {\n    2\n}\n"]) { first, _ in first }
        let beside = try Self.package(besideFiles, utf16: wide)
        defer { beside.remove() }
        // Given only files it can't read, the real tool exits 64.
        let lonely = try FakeTool.makeCloneDetector(
            outputs: [:],
            errors: ["default": "Error: no .swift files found\n"],
            statuses: ["default": 64, "--type3": 64, "--sequence": 64, "--type1": 64]
        )
        defer { CloneHarness.remove(lonely) }
        let paired = try Self.tool(subtree: "[]")
        defer { CloneHarness.remove(paired) }

        let empty = try alone.scan(tools: CloneHarness.locator(lonely))
        let mixed = try beside.scan(tools: CloneHarness.locator(paired))

        let skipped = ScanWarning(file: wide, message: "not readable as UTF-8; skipped")
        #expect(empty.warnings.contains(skipped))
        let status = try #require(CloneHarness.status(empty))
        #expect(status.state == .ran && status.reason == nil)
        #expect(empty.clones?.classes.isEmpty == true)
        #expect(empty.clones?.fileListHash == SwiftCloneDetectorAdapter.fileListHash([]))
        let directory = lonely.deletingLastPathComponent().path
        #expect(try FileManager.default.contentsOfDirectory(atPath: directory).contains { $0.hasPrefix("arguments") }
            == false)
        #expect(mixed.warnings.contains(skipped))
        #expect(CloneHarness.status(mixed)?.state == .ran)
        let shared = SwiftCloneDetectorAdapter.sharedArguments
        #expect(CloneHarness.arguments(of: paired, run: "default") == shared + [readable])
        #expect(mixed.clones?.fileListHash == SwiftCloneDetectorAdapter.fileListHash([readable]))
    }

    @Test(
        "a copy ending before it starts, or with a position below 1, fails the collector, and the scan goes on",
        arguments: [
            ([12, 1, 10, 2], "ends before it starts"),
            ([3, 9, 3, 4], "ends before it starts"),
            ([0, 1, 4, 2], "has a position below 1"),
            ([1, 1, 4, 0], "has a position below 1")
        ]
    )
    func malformedCopy(positions: [Int], problem: String) throws {
        let package = try TemporaryPackage([
            "Sources/Lib/Money.swift": "func one() -> Int {\n    let value = 1\n    return value + value\n}\n"
        ])
        defer { package.remove() }
        let copy = { (place: [Int]) in
            "{\"path\": \"Sources/Lib/Money.swift\", \"startLine\": \(place[0]), \"startColumn\": \(place[1]), "
                + "\"endLine\": \(place[2]), \"endColumn\": \(place[3])}"
        }
        let clone = """
            [{"fingerprint": "0000000000000001", "mass": 40, "lineSpan": 3,
              "instances": [\(copy(positions)), \(copy([1, 1, 4, 2]))]}]
            """
        let tool = try Self.tool(subtree: clone)
        defer { CloneHarness.remove(tool) }

        let report = try package.scan(tools: CloneHarness.locator(tool))

        let status = try #require(CloneHarness.status(report))
        #expect(status.state == .failed)
        let span = "\(positions[0]):\(positions[1])-\(positions[2]):\(positions[3])"
        #expect(status.reason == "could not read swiftclonedetector's output: the subtree run reports a copy of "
            + "Sources/Lib/Money.swift at \(span), which \(problem)")
        #expect(report.clones == nil)
        #expect(report.rollups.allSatisfy { $0.clones == nil })
        #expect(report.records.contains { $0.key == "Lib::func one() -> Int" })
    }
}
