import Foundation
@testable import SwiftStatsCore
import Testing

/// Scanner behaviour that doesn't need SwiftPM: a fixed package description
/// stands in for `swift package describe`.
@Suite("Scanner robustness")
struct ScannerRobustnessTests {
    private struct FixedDescriber: PackageDescriber {
        let package: DescribedPackage

        func describePackage(at _: URL) -> DescribedPackage {
            package
        }
    }

    private static func makePackage(_ files: [String: Data]) throws -> URL {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("ScannerRobustnessTests-\(UUID().uuidString)")
        for (path, contents) in files.merging(["Package.swift": Data()], uniquingKeysWith: { first, _ in first }) {
            let url = root.appendingPathComponent(path)
            try FileManager.default.createDirectory(
                at: url.deletingLastPathComponent(),
                withIntermediateDirectories: true
            )
            try contents.write(to: url)
        }
        return root
    }

    private static func scan(_ root: URL, sources: [String]) throws -> ScanReport {
        let target = DescribedTarget(
            name: "Lib",
            type: "library",
            moduleType: "SwiftTarget",
            path: "Sources/Lib",
            sources: sources
        )
        let describer = FixedDescriber(package: DescribedPackage(name: "Probe", targets: [target]))
        return try PackageScanner(describer: describer).scan(packageAt: root)
    }

    @Test("line-1 columns count a byte order mark's 3 bytes, as the compiler does")
    func byteOrderMark() throws {
        let source = "struct S { func bom() { } }\nstruct T { func plain() { } }\n"
        let root = try Self.makePackage([
            "Sources/Lib/Bom.swift": Data([0xEF, 0xBB, 0xBF]) + Data(source.utf8),
            "Sources/Lib/Plain.swift": Data(source.utf8)
        ])
        defer { try? FileManager.default.removeItem(at: root) }

        let records = try Self.scan(root, sources: ["Bom.swift", "Plain.swift"]).records

        #expect(records.map(\.range.start) == [
            SourcePosition(line: 1, column: 15),
            SourcePosition(line: 2, column: 12),
            SourcePosition(line: 1, column: 12),
            SourcePosition(line: 2, column: 12)
        ])
    }

    @Test("a file that isn't UTF-8 is skipped with a warning, not a failure")
    func unreadableFile() throws {
        let root = try Self.makePackage([
            "Sources/Lib/Good.swift": Data("func ok() { }\n".utf8),
            "Sources/Lib/Bad.swift": Data([0xFF, 0xFE, 0x00])
        ])
        defer { try? FileManager.default.removeItem(at: root) }

        let report = try Self.scan(root, sources: ["Bad.swift", "Good.swift"])

        #expect(report.records.map(\.name) == ["ok"])
        let expected = ScanWarning(file: "Sources/Lib/Bad.swift", message: "not readable as UTF-8; skipped")
        #expect(report.warnings == [expected])
    }

    @Test("a failing command's reason comes from stdout when stderr is empty")
    func failureReason() {
        let directory = FileManager.default.temporaryDirectory
        #expect(throws: ScanError.commandFailed("/bin/sh -c echo explained; exit 3", 3, "explained")) {
            try ProcessRunner.run(executable: "/bin/sh", arguments: ["-c", "echo explained; exit 3"], in: directory)
        }
        let script = "echo out; echo err >&2; exit 1"
        #expect(throws: ScanError.commandFailed("/bin/sh -c \(script)", 1, "err")) {
            try ProcessRunner.run(executable: "/bin/sh", arguments: ["-c", script], in: directory)
        }
    }
}
