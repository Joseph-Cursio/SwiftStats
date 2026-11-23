import Foundation
@testable import SwiftStatsCore
import Testing

/// What an interrupted command leaves (PRD §7.11): its child processes are
/// stopped and its temporary files removed, and it still ends by the signal.
@Suite("Interrupt cleanup")
struct InterruptCleanupTests {
    /// How long a run may take to reach `swift-infer`.
    private static let startTimeout: TimeInterval = 120
    /// How long an interrupted run, and its children, may take to end.
    private static let endTimeout: TimeInterval = 15
    /// How long a run that ignores a signal is given to end by it anyway.
    private static let hangupGrace: TimeInterval = 2
    /// How often to look, in microseconds.
    private static let pollInterval: useconds_t = 50_000
    /// The targets the interrupted package indexes.
    private static let targetNames = ["Core", "Impl"]

    /// Waits until `condition` holds or `timeout` passes; whether it held.
    private static func wait(_ timeout: TimeInterval, until condition: () -> Bool) -> Bool {
        let deadline = Date().addingTimeInterval(timeout)
        while condition() == false {
            guard Date() < deadline else {
                return false
            }
            usleep(pollInterval)
        }
        return true
    }

    /// The `swiftstats` built beside this test bundle.
    private static func swiftstats() -> URL {
        var info = Dl_info()
        _ = dladdr(#dsohandle, &info)
        var bundle = URL(fileURLWithPath: info.dli_fname.map { String(cString: $0) } ?? "/")
        while bundle.pathExtension != "xctest", bundle.path != "/" {
            bundle = bundle.deletingLastPathComponent()
        }
        return bundle.deletingLastPathComponent().appendingPathComponent("swiftstats")
    }

    /// The work directory holding the clone at `path`, which is
    /// `<work>/targets/<T>/package`.
    private static func work(holding path: String) -> URL {
        URL(fileURLWithPath: path)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
    }

    /// Whether a process with identifier `pid` exists.
    private static func exists(_ pid: pid_t) -> Bool {
        kill(pid, 0) == 0 || errno != ESRCH
    }

    /// A package with two library targets whose `.swiftstats.yml` runs
    /// `swift-infer` from `tool` and no other external tool, in `directory`.
    private static func package(in directory: URL, tool: URL) throws -> URL {
        let package = directory.appendingPathComponent("Package")
        let targets = targetNames.map { ".target(name: \"\($0)\")" }.joined(separator: ", ")
        let files = [
            "Package.swift": """
            // swift-tools-version:5.9
            import PackageDescription
            let package = Package(name: "Interrupted", targets: [\(targets)])

            """,
            "Sources/Core/Core.swift": "public func core() -> Int { 1 }\n",
            "Sources/Impl/Impl.swift": "public func impl() -> Int { 2 }\n",
            ".swiftstats.yml": """
            collectors:
              swiftinferproperties:
                path: \(tool.path)
              swiftlint:
                enabled: false
              swiftprojectlint:
                enabled: false
              swiftclonedetector:
                enabled: false

            """
        ]
        for (path, contents) in files {
            let url = package.appendingPathComponent(path)
            try FileManager.default.createDirectory(
                at: url.deletingLastPathComponent(),
                withIntermediateDirectories: true
            )
            try contents.write(to: url, atomically: true, encoding: .utf8)
        }
        return package
    }

    /// A `swift-infer` stand-in that, for `index`, appends its process
    /// identifier and working directory to `runs` and sleeps.
    private static func sleepingTool(in directory: URL, runs: URL) throws -> URL {
        let tool = directory.appendingPathComponent("swift-infer")
        let script = """
        #!/bin/sh
        if [ "$1" = "--version" ]; then echo "0.0 (stand-in)"; exit 0; fi
        echo "$$ $(pwd -P)" >> "\(runs.path)"
        exec /bin/sleep 60

        """
        try script.write(to: tool, atomically: true, encoding: .utf8)
        try FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: tool.path)
        return tool
    }

    /// The process identifier and working directory of each run `log` holds.
    private static func runs(in log: URL) -> [[String]] {
        ((try? String(contentsOf: log, encoding: .utf8)) ?? "").split(separator: "\n").map { line in
            line.split(separator: " ", maxSplits: 1).map(String.init)
        }
    }

    /// A `swiftstats scan` of a package in `directory` whose `swift-infer`
    /// runs sleep and are logged to the returned file, started through
    /// `launcher` when one is given.
    private static func startScan(in directory: URL, launcher: URL?) throws -> (scan: Process, runs: URL) {
        let binary = Self.swiftstats()
        try #require(FileManager.default.isExecutableFile(atPath: binary.path))
        let runs = directory.appendingPathComponent("runs.log")
        let package = try Self.package(in: directory, tool: try Self.sleepingTool(in: directory, runs: runs))
        let scan = Process()
        scan.executableURL = launcher ?? binary
        scan.arguments = (launcher == nil ? [] : [binary.path]) + ["scan", package.path, "--no-store"]
        scan.standardOutput = FileHandle.nullDevice
        scan.standardError = FileHandle.nullDevice
        try scan.run()
        return (scan, runs)
    }

    /// Kills `scan` and the runs `log` holds, and removes their copies.
    private static func stop(_ scan: Process, runs log: URL) {
        if scan.isRunning {
            kill(scan.processIdentifier, SIGKILL)
        }
        for run in Self.runs(in: log) {
            if let pid = pid_t(run[0]) {
                kill(pid, SIGKILL)
            }
            try? FileManager.default.removeItem(at: Self.work(holding: run[1]))
        }
    }

    /// A new, empty temporary directory.
    private static func temporaryDirectory() throws -> URL {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent("Interrupt-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        return directory
    }

    @Test("""
        cleaning up interrupts registered processes, killing one that ignores SIGINT and SIGTERM, and removes \
        registered paths
        """)
    func registryCleanUp() throws {
        let registry = ScratchRegistry()
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent("Scratch-\(UUID().uuidString)")
        registry.track(directory)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        try Data("x".utf8).write(to: directory.appendingPathComponent("file"))
        defer { try? FileManager.default.removeItem(at: directory) }
        let sleeper = Process()
        sleeper.executableURL = URL(fileURLWithPath: "/bin/sleep")
        sleeper.arguments = ["60"]
        let stubborn = Process()
        stubborn.executableURL = URL(fileURLWithPath: "/bin/sh")
        let ready = directory.appendingPathComponent("ready")
        stubborn.arguments = ["-c", "trap '' INT TERM; : > '\(ready.path)'; exec /bin/sleep 60"]
        try registry.start(sleeper)
        try registry.start(stubborn)
        defer {
            for process in [sleeper, stubborn] where process.isRunning {
                kill(process.processIdentifier, SIGKILL)
            }
        }
        #expect(registry.registeredProcesses.count == 2)
        try #require(Self.wait(Self.endTimeout) { FileManager.default.fileExists(atPath: ready.path) })

        registry.cleanUp()

        try #require(Self.wait(Self.endTimeout) { sleeper.isRunning == false && stubborn.isRunning == false })
        #expect(stubborn.terminationReason == .uncaughtSignal && stubborn.terminationStatus == SIGKILL)
        #expect(FileManager.default.fileExists(atPath: directory.path) == false)
        #expect(registry.registeredPaths.isEmpty)
    }

    @Test("""
        cleaning up interrupts first, so a child that, like swift test, stops its own grandchild in another \
        process group on SIGINT and ignores SIGTERM leaves no grandchild running
        """)
    func grandchildInterrupt() throws {
        let registry = ScratchRegistry()
        let directory = try Self.temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let pidFile = directory.appendingPathComponent("grandchild")
        // `set -m` starts the background job in a process group of its own,
        // where signals to the child's group never reach it.
        let child = Process()
        child.executableURL = URL(fileURLWithPath: "/bin/sh")
        child.arguments = [
            "-c",
            """
            set -m
            /bin/sleep 60 &
            grandchild=$!
            trap 'kill $grandchild; exit 130' INT
            trap '' TERM
            echo $grandchild > '\(pidFile.path)'
            wait
            """
        ]
        try registry.start(child)
        var grandchild: pid_t?
        defer {
            if child.isRunning {
                kill(child.processIdentifier, SIGKILL)
            }
            if let grandchild {
                kill(grandchild, SIGKILL)
            }
        }
        try #require(Self.wait(Self.endTimeout) {
            let text = (try? String(contentsOf: pidFile, encoding: .utf8)) ?? ""
            grandchild = pid_t(text.trimmingCharacters(in: .whitespacesAndNewlines))
            return grandchild != nil
        })
        let pid = try #require(grandchild)
        #expect(Self.exists(pid))

        registry.cleanUp()

        #expect(Self.wait(Self.endTimeout) { child.isRunning == false })
        #expect(child.terminationReason == .exit && child.terminationStatus == 130)
        #expect(Self.wait(Self.endTimeout) { Self.exists(pid) == false })
    }

    @Test("""
        the signals cleaned up after are SIGINT, SIGTERM, SIGHUP and SIGQUIT (Ctrl-\\, pressed after Ctrl-C)
        """)
    func cleanedSignals() {
        // SIGQUIT isn't sent to the real binary below: a process it ends
        // leaves a crash report in ~/Library/Logs/DiagnosticReports on
        // every test run, however `ulimit -c` stands. The handler is the
        // same for each signal, so SIGTERM's run covers its cleanup.
        #expect(Set(InterruptCleanup.signals) == [SIGINT, SIGTERM, SIGHUP, SIGQUIT])
    }

    @Test("""
        swiftstats scan interrupted by SIGTERM while swift-infer runs stops the runs, removes the copy and \
        still ends by SIGTERM
        """)
    func interruptedScan() throws {
        let directory = try Self.temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let (scan, runs) = try Self.startScan(in: directory, launcher: nil)
        defer { Self.stop(scan, runs: runs) }
        try #require(Self.wait(Self.startTimeout) { Self.runs(in: runs).count == Self.targetNames.count })

        scan.terminate()

        try #require(Self.wait(Self.endTimeout) { scan.isRunning == false })
        #expect(scan.terminationReason == .uncaughtSignal && scan.terminationStatus == SIGTERM)
        let children = Self.runs(in: runs).compactMap { pid_t($0[0]) }
        #expect(children.count == Self.targetNames.count)
        #expect(Self.wait(Self.endTimeout) { children.allSatisfy { Self.exists($0) == false } })
        let copies = Self.runs(in: runs).map(\.[1])
        #expect(copies.allSatisfy { FileManager.default.fileExists(atPath: $0) == false })
        let work = Self.work(holding: copies[0])
        #expect(work.lastPathComponent.hasPrefix("SwiftStats-"))
        #expect(FileManager.default.fileExists(atPath: work.path) == false)
    }

    @Test("swiftstats scan started by nohup keeps SIGHUP ignored: a hangup leaves the scan and its runs going")
    func hangupUnderNohup() throws {
        let directory = try Self.temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let (scan, runs) = try Self.startScan(in: directory, launcher: URL(fileURLWithPath: "/usr/bin/nohup"))
        defer { Self.stop(scan, runs: runs) }
        try #require(Self.wait(Self.startTimeout) { Self.runs(in: runs).count == Self.targetNames.count })

        kill(scan.processIdentifier, SIGHUP)

        // Given time to end, it is still running.
        #expect(Self.wait(Self.hangupGrace) { scan.isRunning == false } == false)
        let children = Self.runs(in: runs).compactMap { pid_t($0[0]) }
        #expect(children.allSatisfy(Self.exists))
        scan.terminate()
        try #require(Self.wait(Self.endTimeout) { scan.isRunning == false })
        #expect(scan.terminationReason == .uncaughtSignal && scan.terminationStatus == SIGTERM)
        #expect(Self.wait(Self.endTimeout) { children.allSatisfy { Self.exists($0) == false } })
    }
}
