//
//  PeripheryRetentionTests.swift
//  SwiftStatsCoreTests
//
//  More of the `periphery` collector's runs (M7, design §5.2 as built,
//  reviews C14 and C15), on a copy of the Index fixture scanned against its
//  recorded build and dump with a fake outskirts, as `PeripheryAdapterTests`
//  scans it: a package target a library-product target re-exports is
//  retained, with the index and without it; and a run stopped by a signal
//  fails the collector, keeping nothing. Serialized, each scan on a thread
//  of its own, as the index collector's tests are.
//

import Foundation
@testable import SwiftStatsCore
import Testing

/// Re-exported targets retained, and a run stopped by a signal.
@Suite("Periphery collector: retention and signals", .serialized)
struct PeripheryRetentionTests {
    /// The periphery collector's tests, whose helpers these use.
    private typealias Shared = PeripheryAdapterTests

    @Test("""
        a package target a library-product target re-exports with @_exported import is retained too, by C99 name, \
        and stored among the library modules; with the index disabled the collector finds it the same way
        """)
    func reexportedModules() async throws {
        var scan = try IndexFixtureScan()
        scan.prepare = { fixture in
            // Appended, so the recorded index's positions still hold.
            let file = fixture.package.root.appendingPathComponent("Sources/IndexCore/Dependency.swift")
            let text = try String(contentsOf: file, encoding: .utf8)
            try (text + "\n@_exported import index_support\n").write(to: file, atomically: true, encoding: .utf8)
        }
        let retained = ["IndexCore", "index_kit", "index_support"]
        let targets = ["IndexCore", "index-kit", "index-support"]
        try await Shared.scanning(try FakePeriphery.recorded(), with: scan) { fixture, outcome, fake in
            let build = fixture.paths.build
            #expect(fake.arguments(of: .production) == Shared.arguments(.production, build: build, retained: retained))
            #expect(outcome.statuses["periphery"]?.options == Shared.options(
                retained: retained,
                targets: targets.joined(separator: ", ")
            ))
            #expect(outcome.report.index?.libraryModules == targets)
        }

        scan.extra = "  index:\n    enabled: false\n"
        try await Shared.scanning(try FakePeriphery.recorded(), with: scan) { fixture, outcome, fake in
            #expect(outcome.statuses["index"]?.reason == "disabled by collectors.index.enabled")
            let build = fixture.paths.build
            #expect(fake.arguments(of: .roots) == Shared.arguments(.roots, build: build, retained: retained))
            #expect(outcome.statuses["periphery"]?.options.contains(PeripheryCommand.retainOption(targets: targets))
                == true)
        }
    }

    @Test("""
        a production run stopped by a signal after writing its output fails the collector, saying which signal \
        with its standard error, and keeps no dead-code results from either run
        """)
    func signalledRun() async throws {
        var killed = try FakePeriphery.recorded()
        killed.errors[.production] = FakePeriphery.xcodeWarning + "\nfatal error: out of memory\n"
        killed.signals[.production] = SIGTERM
        try await Shared.scanning(killed, with: try IndexFixtureScan()) { _, outcome, fake in
            let periphery = try #require(outcome.statuses["periphery"])
            #expect(periphery.state == .failed)
            #expect(periphery.reason
                == "outskirts scan (production) was stopped by signal 15: fatal error: out of memory")
            #expect(fake.calls == ["version", "roots", "production"])
            #expect(outcome.report.deadCode == nil)
            #expect(outcome.statuses["index"]?.state == .ran)
        }
    }
}
