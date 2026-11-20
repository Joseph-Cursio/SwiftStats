import Foundation
@testable import SwiftStatsCore
import Testing

/// How SwiftCloneDetector runs (PRD §7.12, §6.5): four runs from the
/// package root over the production files given explicitly, exits 0 and 2
/// accepted, failures reported without the file list, no run when there is
/// nothing to read, and copies on a first line after a byte order mark
/// lined up with their records.
@Suite("SwiftCloneDetector runs")
struct CloneRunTests {
    /// A report of `clones`, a JSON array, as the tool writes it.
    private static func report(_ clones: String) -> String {
        """
        {"cloneCount": 0, "clones": \(clones), "duplicatedLines": 0, "fileCount": 2, "mode": "type1-2",
         "tool": "swift-clone-detector", "version": "0.1.0"}
        """
    }

    /// The clone detector's status in a scan of `package` with `tool`.
    private static func scan(_ package: TemporaryPackage, _ tool: URL) throws -> ScanReport {
        try package.scan(tools: CloneHarness.locator(tool))
    }

    @Test("""
        each of the four runs starts from the package root, with every result-changing flag, over the \
        production files byte-sorted, generated and test files left out
        """)
    func arguments() throws {
        let tool = try CloneHarness.recordedTool()
        defer { CloneHarness.remove(tool) }

        let report = try CloneHarness.scan(tool)

        let status = try #require(CloneHarness.status(report))
        #expect(status.state == .ran)
        #expect(status.version == "0.1.0")
        let shared = SwiftCloneDetectorAdapter.sharedArguments
        #expect(shared == [
            "--format", "json", "--include-generated", "--min-mass", "20", "--min-lines", "2",
            "--min-distinct-identifiers", "0", "--similarity", "0.85", "--min-distinctiveness", "1.55",
            "--min-identifier-overlap", "0.25"
        ])
        let flags: [String: [String]] = [
            "default": [], "--type3": ["--type3"], "--sequence": ["--sequence"], "--type1": ["--type1"]
        ]
        for (run, flag) in flags {
            #expect(CloneHarness.arguments(of: tool, run: run) == shared + flag + CloneHarness.files)
            #expect(FakeTool.log("cwd-\(run).txt", of: tool) == [CloneHarness.fixture.resolvingSymlinksInPath().path])
        }
        let joined = shared.joined(separator: " ")
        #expect(status.options == [
            "subtree: \(joined)",
            "near-miss: \(joined) --type3",
            "sequence: \(joined) --sequence",
            "type1: \(joined) --type1",
            "files: production files after exclusion, generated ones left out, root-relative, byte-sorted, "
                + "given explicitly"
        ])
    }

    @Test("""
        exit 0 succeeds; exit 64, or a report naming another tool, fails the collector with a reason \
        that leaves out the files, and nothing is counted
        """)
    func exitStatuses() throws {
        let quiet = try FakeTool.makeCloneDetector(
            outputs: try CloneHarness.outputs(),
            errors: [:],
            statuses: ["default": 0, "--type3": 0, "--sequence": 0, "--type1": 0]
        )
        defer { CloneHarness.remove(quiet) }
        let usage = try FakeTool.makeCloneDetector(
            outputs: try CloneHarness.outputs(),
            errors: ["--type3": "Error: no .swift files found\nUsage: swift-clone-detector [<options>]\n"],
            statuses: ["--type3": 64]
        )
        defer { CloneHarness.remove(usage) }
        var outputs = try CloneHarness.outputs()
        outputs["default"] = Self.report("[]").replacingOccurrences(of: "swift-clone-detector", with: "other")
        let other = try FakeTool.makeCloneDetector(outputs: outputs, errors: [:], statuses: [:])
        defer { CloneHarness.remove(other) }

        let ran = try CloneHarness.scan(quiet)
        let failed = try CloneHarness.scan(usage)
        let misnamed = try CloneHarness.scan(other)

        #expect(CloneHarness.status(ran)?.state == .ran)
        #expect(ran.clones?.classes.count == 11)
        #expect(CloneHarness.status(failed)?.state == .failed)
        #expect(CloneHarness.status(failed)?.reason == """
            `swift-clone-detector --type3` over 8 files exited with status 64: Error: no .swift files found
            Usage: swift-clone-detector [<options>]
            """)
        #expect(CloneHarness.status(failed)?.options == SwiftCloneDetectorAdapter.options)
        #expect(CloneHarness.status(misnamed)?.state == .failed)
        #expect(CloneHarness.status(misnamed)?.reason
            == "could not read swiftclonedetector's output: the subtree run names its tool \"other\"")
        for report in [failed, misnamed] {
            #expect(report.clones == nil)
            #expect(report.rollups.allSatisfy { $0.clones == nil })
        }
        #expect(MarkdownClones.render(failed).first?.hasPrefix("Not collected: failed, `swift-clone-detector") == true)
    }

    @Test("with no file to read the tool isn't run, and the collector ran with no classes; disabled, it is skipped")
    func nothingToRead() throws {
        let package = try TemporaryPackage([
            "Sources/Lib/Copies.swift": "// DO NOT EDIT: generated.\nfunc copy() -> Int {\n    1\n}\n",
            "Tests/LibTests/CopyTests.swift": "func check() -> Int {\n    1\n}\n"
        ])
        defer { package.remove() }
        let disabled = try TemporaryPackage([
            "Sources/Lib/One.swift": "func one() -> Int {\n    1\n}\n",
            ".swiftstats.yml": "collectors:\n  swiftclonedetector:\n    enabled: false\n"
        ])
        defer { disabled.remove() }
        let tool = try CloneHarness.recordedTool()
        defer { CloneHarness.remove(tool) }

        let empty = try Self.scan(package, tool)
        let skipped = try Self.scan(disabled, tool)

        let directory = tool.deletingLastPathComponent().path
        #expect(try FileManager.default.contentsOfDirectory(atPath: directory).contains { $0.hasPrefix("arguments") }
            == false)
        let status = try #require(CloneHarness.status(empty))
        #expect(status.state == .ran && status.version == nil && status.reason == nil)
        #expect(empty.clones?.classes.isEmpty == true)
        #expect(empty.clones?.fileListHash == "sha256:" + ContentHash.sha256(Data()))
        let lib = empty.rollups.first { $0.name == "Lib" }
        #expect(lib?.clones?.classes == CloneRollup.Classes(exact: 0, renamed: 0, sequence: 0, nearMiss: 0))
        #expect(lib?.clones?.clonedLines == 0)
        #expect(CloneHarness.status(skipped)?.state == .skipped)
        #expect(CloneHarness.status(skipped)?.reason == "disabled by collectors.swiftclonedetector.enabled")
        #expect(skipped.clones == nil)
        #expect(skipped.rollups.allSatisfy { $0.clones == nil })
    }

    @Test("a copy on line 1 of a file starting with a byte order mark lines up with its record")
    func byteOrderMark() throws {
        let body = "() -> Int {\n    let value = 1\n    return value + value\n}\n"
        let package = try TemporaryPackage([
            "Sources/Lib/Marked.swift": "\u{FEFF}func one" + body,
            "Sources/Lib/Plain.swift": "func two" + body
        ])
        defer { package.remove() }
        let instance = { (file: String) in
            "{\"path\": \"Sources/Lib/\(file)\", \"startLine\": 1, \"startColumn\": 1, "
                + "\"endLine\": 4, \"endColumn\": 2}"
        }
        let clone = """
            [{"fingerprint": "0000000000000001", "mass": 40, "lineSpan": 4,
              "instances": [\(instance("Marked.swift")), \(instance("Plain.swift"))]}]
            """
        let tool = try FakeTool.makeCloneDetector(
            outputs: [
                "default": Self.report(clone),
                "--type3": Self.report("[]"),
                "--sequence": Self.report("[]"),
                "--type1": Self.report("[]")
            ],
            errors: [:],
            statuses: [:]
        )
        defer { CloneHarness.remove(tool) }

        let report = try Self.scan(package, tool)

        let instances = try #require(report.clones?.classes.first?.instances)
        let records = report.records.filter { $0.kind == .function }.sorted { $0.file < $1.file }
        #expect(instances.map(\.range) == records.map(\.range))
        #expect(instances.map(\.range.start.column) == [4, 1])
        #expect(instances.map(\.containing) == ["Lib::func one() -> Int", "Lib::func two() -> Int"])
        #expect(instances.map(\.wholes) == [["Lib::func one() -> Int"], ["Lib::func two() -> Int"]])
    }
}
