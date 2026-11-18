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

    @Test("a type declared with different first parents gets a Sitrep warning, sorted before file warnings")
    func sitrepConflictingParents() throws {
        let root = try Self.makePackage([
            "Sources/Lib/A.swift": Data("struct Row: View { var body: some View { Text(\"row\") } }\n".utf8),
            "Sources/Lib/B.swift": Data("struct Row: Codable { }\n".utf8),
            ".swiftstats.yml": Data("store: stats.sqlite\n".utf8)
        ])
        defer { try? FileManager.default.removeItem(at: root) }

        let warnings = try Self.scan(root, sources: ["A.swift", "B.swift"]).warnings

        #expect(warnings.map(\.file) == [nil, ".swiftstats.yml"])
        #expect(warnings.first?.message == "sitrep: Row is declared with different first parents; "
            + "its UIKit and SwiftUI line counts follow the first declaration in path order")
    }

    @Test("records and types at the same position sort by key and name; on one line, by column")
    func orderTieBreakers() throws {
        let records = CollectorHarness.collect("struct Pair { func first() { }; func second() { } }")
        let first = try #require(records.first)
        let renamed = first.replacingKeys(key: first.key + " #2", parentKey: first.parentKey)

        #expect(records.map(\.name) == ["first", "second"])
        #expect(PackageScanner.recordOrder(records[0], records[1]))
        #expect(PackageScanner.recordOrder(first, renamed))
        #expect(PackageScanner.recordOrder(renamed, first) == false)

        let type = try #require(CollectorHarness.types("struct Pair { }").first)
        let twin = TypeRecord(
            module: type.module,
            kind: type.kind,
            name: "Pairs",
            file: type.file,
            range: type.range,
            strippedLines: type.strippedLines,
            memberCount: type.memberCount,
            isLocal: type.isLocal,
            ifConfig: type.ifConfig
        )
        #expect(PackageScanner.typeOrder(type, twin))
        #expect(PackageScanner.typeOrder(twin, type) == false)
    }

    @Test("SwiftPM output that doesn't decode is an error naming the package")
    func undecodableDescription() {
        let root = URL(fileURLWithPath: "/tmp/Probe")
        do {
            _ = try SwiftPMPackageDescriber.decode(Data("{\"name\": 1}".utf8), packageRoot: root)
            Issue.record("a description without targets should not decode")
        } catch {
            #expect("\(error)".hasPrefix("could not read SwiftPM's description of /tmp/Probe: "))
        }
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
