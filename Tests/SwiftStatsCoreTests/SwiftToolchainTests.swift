import Foundation
@testable import SwiftStatsCore
import Testing

/// The toolchain a resolved `swift` selects (M5, split out of the coverage
/// collector's in M7) against a fake toolchain: its own `swift`, its
/// directory, its runtime resources, where its `libIndexStore.dylib` is,
/// and the version line, asking the resolved `swift` for the target info
/// only.
@Suite("Swift toolchain")
struct SwiftToolchainTests {
    /// Discovers the toolchain of `scenario`'s fake through its proxy, in a
    /// temporary package, and passes it and the fake to `body`; when
    /// `targetInfo` is given, the proxy prints what it makes of the fake's
    /// directory in place of its runtime resource path; when `linked` is
    /// true, the fake's `swift` is a symlink to `swift-frontend` beside it,
    /// as a real toolchain's is.
    private static func discover(
        _ scenario: FakeToolchain.Scenario,
        targetInfo: ((String) -> String)? = nil,
        linked: Bool = false,
        _ body: (SwiftToolchain, FakeToolchain) throws -> Void
    ) throws {
        let fake = try FakeToolchain.make(scenario)
        defer { fake.remove() }
        if linked {
            let frontend = fake.swift.deletingLastPathComponent().appendingPathComponent("swift-frontend")
            try FileManager.default.moveItem(at: fake.swift, to: frontend)
            try FileManager.default.createSymbolicLink(atPath: fake.swift.path, withDestinationPath: "swift-frontend")
        }
        if let targetInfo {
            // The fake's directory is only known once it is made, so its
            // scenario file is written here; the proxy reads it when run.
            let file = fake.directory.appendingPathComponent("scenario/target-info")
            try targetInfo(fake.directory.path).write(to: file, atomically: true, encoding: .utf8)
        }
        let package = try TemporaryPackage(["Sources/Lib/Lib.swift": "public func one() -> Int { 1 }\n"])
        defer { package.remove() }
        let command = CoverageCommand(
            root: package.root,
            build: package.root.appendingPathComponent(".swiftstats/index-build"),
            toolchain: nil
        )
        try body(try SwiftToolchain.discover(swift: fake.proxy, command: command), fake)
    }

    @Test("""
        the resolved swift's target info names the toolchain: its own swift, its directory, its runtime \
        resources, libIndexStore.dylib beside them, and the version line of its own swift
        """)
    func discovered() throws {
        try Self.discover(try FakeToolchain.recorded()) { toolchain, fake in
            let real = MutationRunHarness.realPath
            #expect(real(toolchain.swift) == real(fake.swift))
            #expect(real(toolchain.directory) == real(fake.directory))
            #expect(real(toolchain.runtimeResources) == real(fake.directory.appendingPathComponent("usr/lib/swift")))
            #expect(toolchain.libIndexStore.lastPathComponent == "libIndexStore.dylib")
            #expect(real(toolchain.libIndexStore.deletingLastPathComponent())
                == real(fake.directory.appendingPathComponent("usr/lib")))
            #expect(toolchain.swiftVersion == "Apple Swift version 9.9 (fake)")
            #expect(fake.calls(of: "proxy") == ["-print-target-info"])
            #expect(fake.calls(of: "swift") == ["--version"])
            #expect(fake.calls(of: "llvm-profdata").isEmpty && fake.calls(of: "xcrun").isEmpty)
        }
    }

    @Test("""
        a swift that is a symlink to swift-frontend is kept by its own name, since swift-frontend acts as \
        swift only when run as swift
        """)
    func symlinkKept() throws {
        try Self.discover(try FakeToolchain.recorded(), linked: true) { toolchain, fake in
            let real = MutationRunHarness.realPath
            #expect(toolchain.swift.lastPathComponent == "swift")
            #expect(real(toolchain.swift.deletingLastPathComponent())
                == real(fake.directory.appendingPathComponent("usr/bin")))
            #expect(real(toolchain.directory) == real(fake.directory))
            #expect(toolchain.swiftVersion == "Apple Swift version 9.9 (fake)")
        }
    }

    @Test("a runtime resource path with . and .. components is standardized before the paths beside it are taken")
    func standardized() throws {
        let targetInfo = { (top: String) in
            #"{"paths":{"runtimeResourcePath":"\#(top)/usr/./lib/swift/../swift"}}"#
        }
        try Self.discover(try FakeToolchain.recorded(), targetInfo: targetInfo) { toolchain, fake in
            let real = MutationRunHarness.realPath
            let paths = [toolchain.runtimeResources, toolchain.libIndexStore, toolchain.swift, toolchain.directory]
            #expect(paths.allSatisfy { $0.pathComponents.contains(".") == false })
            #expect(paths.allSatisfy { $0.pathComponents.contains("..") == false })
            #expect(real(toolchain.runtimeResources) == real(fake.directory.appendingPathComponent("usr/lib/swift")))
            #expect(real(toolchain.libIndexStore.deletingLastPathComponent())
                == real(fake.directory.appendingPathComponent("usr/lib")))
            #expect(real(toolchain.swift) == real(fake.swift))
            #expect(real(toolchain.directory) == real(fake.directory))
        }
    }
}
