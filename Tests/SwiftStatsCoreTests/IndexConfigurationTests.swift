import Foundation
@testable import SwiftStatsCore
import Testing

/// The T1 group's configuration (M7, design §1.1): `collectors.build`,
/// `collectors.index` and `collectors.periphery` take `enabled`; only
/// `periphery` takes a `path` (the `outskirts` executable), since the build
/// uses the coverage collector's `swift` and the index is read in process;
/// none takes `arguments`, and their `options` are accepted with a warning.
@Suite("Index configuration")
struct IndexConfigurationTests {
    /// The configuration `text` holds, or the error parsing it gives.
    private static func parsed(_ text: String) -> Result<SwiftStatsConfiguration, ScanError> {
        Result { try SwiftStatsConfiguration.parse(text, path: "c.yml") }.mapError { error in
            error as? ScanError ?? .configurationInvalid("c.yml", "\(error)")
        }
    }

    /// The error parsing `text`, or nil when it parses.
    private static func error(_ text: String) -> ScanError? {
        guard case .failure(let error) = parsed(text) else {
            return nil
        }
        return error
    }

    @Test("collectors.build, .index and .periphery take enabled, and periphery takes the outskirts path")
    func configuration() throws {
        let text = """
        collectors:
          build:
            enabled: false
          index:
            enabled: true
          periphery:
            enabled: true
            path: tools/outskirts
        """
        let configuration = try SwiftStatsConfiguration.parse(text, path: "c.yml")
        let bare = try SwiftStatsConfiguration.parse("collectors:\n  build:\n  index:\n  periphery:\n", path: "c.yml")

        #expect(configuration.collectors == [
            "build": CollectorSettings(enabled: false, path: nil),
            "index": CollectorSettings(enabled: true, path: nil),
            "periphery": CollectorSettings(enabled: true, path: "tools/outskirts")
        ])
        #expect(configuration.unusedKeys.isEmpty)
        #expect(bare.collectors == [
            "build": CollectorSettings(enabled: true, path: nil),
            "index": CollectorSettings(enabled: true, path: nil),
            "periphery": CollectorSettings(enabled: true, path: nil)
        ])
        #expect(bare.unusedKeys.isEmpty)
    }

    @Test("enabled must be a boolean under each of the three, naming the key")
    func enabledErrors() {
        for name in ["build", "index", "periphery"] {
            #expect(
                Self.error("collectors:\n  \(name):\n    enabled: sometimes\n")
                    == .configurationInvalid("c.yml", "`collectors.\(name).enabled` must be true or false"),
                "\(name)"
            )
        }
    }

    @Test("""
        collectors.build.path points at the coverage collector's swift, collectors.index.path is refused as \
        any in-process collector's, and a periphery path that isn't a string is an error
        """)
    func pathErrors() {
        #expect(Self.error("collectors:\n  build:\n    path: /usr/bin/swift\n") == .configurationInvalid(
            "c.yml",
            "`collectors.build.path`: the build uses the coverage collector's swift; set collectors.coverage.path"
        ))
        #expect(Self.error("collectors:\n  index:\n    path: tools/reader\n") == .configurationInvalid(
            "c.yml",
            "`collectors.index.path`: a collector SwiftStats runs itself has no path"
        ))
        #expect(Self.error("collectors:\n  periphery:\n    path: [outskirts]\n") == .configurationInvalid(
            "c.yml",
            "`collectors.periphery.path` must be a path"
        ))
    }

    @Test("none of the three takes arguments, with the existing message")
    func argumentsRefused() {
        for name in ["build", "index", "periphery"] {
            #expect(
                Self.error("collectors:\n  \(name):\n    arguments: [\"--skip\", \"A\"]\n") == .configurationInvalid(
                    "c.yml",
                    "`collectors.\(name).arguments`: only the coverage and swiftmutator collectors take arguments"
                ),
                "\(name)"
            )
        }
    }

    @Test("their options are accepted, warned about as not used yet, and an unknown key is still an error")
    func optionsWarned() throws {
        let text = """
        collectors:
          build:
            options: {jobs: 4}
          index:
            options: [--locals]
          periphery:
            options: {strict: true}
        """
        let configuration = try SwiftStatsConfiguration.parse(text, path: "c.yml")

        #expect(configuration.unusedKeys == [
            "collectors.build.options", "collectors.index.options", "collectors.periphery.options"
        ])
        #expect(PackageScanner.unusedKeyWarnings(configuration).map(\.message).sorted() == [
            "`collectors.build.options` is accepted but not used yet; it has no effect on this scan",
            "`collectors.index.options` is accepted but not used yet; it has no effect on this scan",
            "`collectors.periphery.options` is accepted but not used yet; it has no effect on this scan"
        ])
        #expect(Self.error("collectors:\n  periphery:\n    retain: public\n") == .configurationInvalid(
            "c.yml",
            "unknown key(s): collectors.periphery.retain"
        ))
    }
}
