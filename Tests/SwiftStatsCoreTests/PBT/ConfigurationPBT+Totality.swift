//
//  ConfigurationPBT+Totality.swift
//  SwiftStatsCoreTests
//
//  P11.1's examples, each calling its shared check: configurations
//  holding every section PRD §10.1 names, in block and flow style; the
//  base-60 `workers` texts that trapped in Yams (design B30), kept as
//  regression entries; YAML's corners (tags, anchors, a merge key, two
//  documents, a control character, deep nesting); a file starting with a
//  byte order mark, which `load` drops before `parse` reads the text; and
//  the meta-test feeding planted defects' readings to the check.
//

import Foundation
@testable import SwiftStatsCore
import Testing

/// P11.1's examples and planted defects.
extension ConfigurationPBT {
    /// A configuration holding every section PRD §10.1 names.
    static let everySection = """
        excluded:
          - Sources/Generated
          - "**/*.generated.swift"
        generated: []
        store: .swiftstats/stats.sqlite
        history:
          window: 30d
          fix_patterns: ['\\bfix\\b']
          repeat_window: 1d
          half_life: 106751991167300d
          bulk_files: 1
          ignore_revs: [abcdef0]
          coupling:
            min_support: 2
        signals:
          hotspot:
            threshold: 100
          weak-tests: {coverage: 0, score: 100, mutants: 1000000}
          genuinely-under-tested: {ratio: 5e-324}
          uneven-clone-mutation: {high: 50.00000000000001, low: 50}
          hidden-coupling: {support: 1, confidence: 50}
        collectors:
          coverage:
            path: tools/swift
            arguments: [--skip, Slow]
          swiftmutator:
            enabled: on
            options: {workers: 0x10, timeout: 86400}
          index: ~
          jazzy: {options: [--strict]}

        """

    /// Base-60 `workers` texts whose places, a place's value or its sign
    /// pass `Int`, which trapped in Yams before B30's fix.
    static let baseSixtyEntries = ConfigGen.baseSixtyTraps.map { spelling in
        CorpusEntry(
            input: "collectors:\n  swiftmutator:\n    options:\n      workers: \(spelling)\n",
            pins: "B30: workers \(spelling) trapped in Yams' base-60 reading"
        )
    }

    @Test("a configuration holding every section PRD 10.1 names reads, in block style and in flow style from the top")
    func everySectionReads() throws {
        let flow = """
            {store: s.sqlite, history: {window: 1d, coupling: {min_support: 2}}, \
            signals: {hotspot: {threshold: 5e-324}}, \
            collectors: {swiftmutator: {options: {workers: 1:30}}, swiftlint: {enabled: no}}}
            """

        for text in [Self.everySection, flow, Self.everySection.replacingOccurrences(of: "\n", with: "\r\n")] {
            let read = Read { try SwiftStatsConfiguration.parse(text, path: Self.file) }

            #expect(Self.checkTotal(isValid: true, read: read))
        }
        let configuration = try SwiftStatsConfiguration.parse(Self.everySection, path: Self.file)
        #expect(configuration.collectors["swiftmutator"]?.workers == 16)
        #expect(configuration.unusedKeys == ["collectors.jazzy", "collectors.jazzy.options"])
    }

    @Test("a base-60 workers past Int is a configuration error, not a trap", arguments: baseSixtyEntries)
    func baseSixtyWorkersRefused(entry: CorpusEntry<String>) {
        let read = Read { try SwiftStatsConfiguration.parse(entry.input, path: Self.file) }

        #expect(Self.checkTotal(isValid: false, read: read))
        #expect(throws: ScanError.self) { try read.get() }
    }

    @Test("""
        YAML's corners read or name a configuration error: tags, anchors, a merge key, keys that aren't text, two \
        documents, a control character, an alias to nothing, deep nesting
        """)
    func yamlCornersRead() {
        let texts = [
            "excluded: !!binary aGVsbG8=\n", "history: &a {window: 3d}\nsignals: *a\n",
            "history:\n  <<: {window: 3d}\n", "[a, b]: c\n", "!t excluded: [b]\n", "--- 1\n--- 2\n",
            "excluded: [a\u{0}b]\n", "excluded: *nowhere\n",
            "excluded: " + String(repeating: "[", count: 100) + String(repeating: "]", count: 100)
        ]

        for text in texts {
            let read = Read { try SwiftStatsConfiguration.parse(text, path: Self.file) }

            #expect(Self.checkTotal(isValid: false, read: read), "\(text.debugDescription)")
        }
    }

    @Test("a file starting with a byte order mark loads: the mark is dropped as the file is read, before parse")
    func byteOrderMarkDropped() throws {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("SwiftStatsConfigPBT-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let file = directory.appendingPathComponent(SwiftStatsConfiguration.fileName)
        try Data([0xEF, 0xBB, 0xBF] + Array("store: a.sqlite\nexcluded: [x]\n".utf8)).write(to: file)
        let read = Read { try SwiftStatsConfiguration.load(file, root: directory) }

        #expect(Self.checkTotal(isValid: true, read: read))
        #expect(try read.get().excluded == ["x"])
    }

    @Test("a planted defect's reading of a text fails P11.1's law")
    func totalityDefectsDetected() {
        let named = ScanError.configurationInvalid(Self.file, "unknown key(s): store")

        #expect(Self.checkTotal(isValid: false, read: .failure(named)))
        PlantedDefect.expectDetected("another error thrown, unwrapped", sourceLocation: #_sourceLocation) {
            Self.checkTotal(isValid: false, read: .failure(CocoaError(.propertyListReadCorrupt)))
        }
        PlantedDefect.expectDetected("an error naming another file", sourceLocation: #_sourceLocation) {
            Self.checkTotal(isValid: false, read: .failure(ScanError.configurationInvalid("other.yml", "x")))
        }
        PlantedDefect.expectDetected("a valid configuration refused", sourceLocation: #_sourceLocation) {
            Self.checkTotal(isValid: true, read: .failure(named))
        }
    }
}
