//
//  BuildSession.swift
//  SwiftStatsCore
//
//  The T1 build's commands (M7, design §1.3), once the toolchain is known,
//  in order, under `.swiftstats/index.lock` (`IndexLock`, which
//  `BuildAdapter.run` takes before the session and holds until the
//  products are read): resolve the build directory,
//  `.swiftstats/index-build`, to its real path, which every later use takes (the build's `--scratch-path`, the
//  store, the build class of timings and warnings); keep `Package.resolved`
//  to put back, as the coverage run does; describe the package with the
//  toolchain's own `swift`, the scratch path before the subcommand (after
//  it, `describe` writes nothing), keeping the description in the build
//  directory and mapping each C99 module name to its target; remove the
//  root package's intermediates, named after the manifest, so the build
//  re-times and re-diagnoses every root file while dependencies stay warm
//  (noting when a build directory holds none, since a later Swift Build
//  layout would otherwise leave timings silently partial); build (§1.4),
//  standard output and standard error written to files, never pipes; put
//  `Package.resolved` back, whether the build succeeded, failed or was
//  interrupted (`ScratchRegistry` does on an interruption); hash the
//  scanned files again, listing those changed since they were parsed; and
//  check that the build wrote an index store. A failed build's reason is
//  its last standard-error lines that aren't timing lines; a toolchain
//  rejecting `--build-system swiftbuild` is told apart by its argument
//  parser's exit status, 64, with `--build-system` in its standard error
//  (the coverage run's test alone would also take a compile error whose
//  source snippet shows the flag).
//

import Foundation

/// The commands of one T1 build.
struct BuildSession {
    /// What a build that ran left for the collectors that read it.
    struct Products: Sendable {
        /// The toolchain that built it.
        let toolchain: SwiftToolchain
        /// The build directory, as its real path.
        let scratch: URL
        /// The package as the toolchain's own `swift package describe`
        /// gives it.
        let package: DescribedPackage
        /// Each target's C99 module name, mapped to the target's name.
        let modules: [String: String]
        /// The scanned files, relative to the package root, whose bytes
        /// changed after they were parsed, sorted.
        let changedFiles: [String]
        /// What the run notes without failing, in order.
        let notes: [String]
        /// Why the `index` and `periphery` collectors can't read the
        /// build's index store; nil when it holds one.
        let storeFailure: String?

        /// The index store, `<scratch>/out`.
        var store: URL {
            scratch.appendingPathComponent(BuildSession.storeDirectory)
        }

        /// The description `describe` printed, as it printed it.
        var describeFile: URL {
            scratch.appendingPathComponent(BuildSession.describeName)
        }

        /// The build's standard output, the `-v` task log.
        var log: URL {
            scratch.appendingPathComponent(BuildSession.logName)
        }

        /// The build's standard error: the timing lines and diagnostics.
        var stderr: URL {
            scratch.appendingPathComponent(BuildSession.stderrName)
        }

        /// Whether the build re-timed every root file: false when the run
        /// noted that it found no root intermediates to remove.
        var complete: Bool {
            notes.contains { $0.hasPrefix(BuildSession.incompleteLead) } == false
        }
    }

    /// What describing and building the package gave.
    private struct Built {
        /// The package's description.
        let package: DescribedPackage
        /// Its module map.
        let modules: [String: String]
        /// What the run notes without failing.
        let notes: [String]
    }

    /// The build directory's name, in the package's `.swiftstats`.
    static let directoryName = "index-build"
    /// The lock's file name, in the package's `.swiftstats`, outside the
    /// build directory, so it never meets SwiftPM's own lock.
    static let lockName = "index.lock"
    /// The file the T1 describe's output is kept in, in the build
    /// directory.
    static let describeName = "swiftstats-describe.json"
    /// The file the build's standard output is written to.
    static let logName = "swiftstats-build.log"
    /// The file the build's standard error is written to.
    static let stderrName = "swiftstats-build.stderr"
    /// The index store's directory in the build directory (Swift Build's
    /// layout).
    static let storeDirectory = "out"
    /// What the store holds when the build wrote one.
    static let unitsPath = "v5/units"
    /// Where Swift Build keeps each package's intermediates, in the store's
    /// directory.
    static let intermediatesDirectory = "Intermediates.noindex"
    /// What the note of a run that found no root intermediates to remove
    /// starts with.
    static let incompleteLead = "timings may be incomplete"
    /// Why a build couldn't take the lock because another holds it.
    static let heldReason = "another scan --index is running in this package"
    /// The frontend flags the build passes, each behind
    /// `-Xswiftc -Xfrontend -Xswiftc`.
    private static let frontendFlags = [
        "-debug-time-function-bodies", "-debug-time-expression-type-checking", "-debug-diagnostic-names"
    ]
    /// The extension Swift Build gives a package's intermediates folder.
    private static let intermediatesExtension = "build"
    /// The status SwiftPM exits with when its argument parser refuses an
    /// argument (`EX_USAGE`), as Swift 6.1.2 refuses `--build-system
    /// swiftbuild`; a build that ran and failed exits 1 (6.4.1, measured).
    private static let usageStatus: Int32 = 64

    /// The toolchain whose own `swift` runs every command.
    let toolchain: SwiftToolchain
    /// Runs the commands in the package root and words their failures;
    /// its build directory is the real path.
    let command: CoverageCommand
    /// The scanned files, with their bytes' hashes when parsed.
    let files: [FileRecord]

    /// The build's arguments after `swift`, with `scratch` as the scratch
    /// path: each flag its own element (design §1.4).
    static func arguments(scratch: String) -> [String] {
        ["build", "--build-tests"] + CoverageSession.buildSystemFlags
            + ["-c", "debug", "-v", "--no-color-diagnostics", "--scratch-path", scratch]
            + ["-Xswiftc", "-index-include-locals"]
            + frontendFlags.flatMap { ["-Xswiftc", "-Xfrontend", "-Xswiftc", $0] }
    }

    /// Each target of `package`, by C99 module name, mapped to its name; a
    /// failure naming the first two targets, by name, that share one.
    static func moduleMap(of package: DescribedPackage) throws -> [String: String] {
        var modules: [String: String] = [:]
        for target in package.targets.sorted(by: { $0.name < $1.name }) {
            if let other = modules[target.c99name] {
                throw CoverageFailure(
                    description: "targets \(other) and \(target.name) share the module name \(target.c99name)"
                )
            }
            modules[target.c99name] = target.name
        }
        return modules
    }

    /// `directory`, created when missing, as its real path (realpath(3)):
    /// through a symlinked `/tmp` or package folder, a spelling that isn't
    /// the real one would miss outskirts' exclude and the build class of
    /// timings.
    static func realPath(creating directory: URL) throws -> URL {
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        guard let resolved = realpath(directory.path, nil) else {
            throw CoverageFailure(description: "could not find the real path of .swiftstats/\(directoryName)")
        }
        defer { free(resolved) }
        return URL(fileURLWithPath: String(cString: resolved))
    }

    /// The reason a build that exited `status` and wrote `text` to
    /// standard error failed for: its last lines that aren't timing lines,
    /// cleaned as a coverage command's are, with `replacements` redacted.
    static func failureReason(status: Int32, stderr text: String, replacing replacements: [(URL, String)]) -> String {
        let kept = text.split(omittingEmptySubsequences: false, whereSeparator: \.isNewline)
            .filter { BuildLineGrammar.timingEntry(String($0)) == nil }
            .joined(separator: "\n")
        let cleaned = CoverageStderr.cleaned(kept, replacing: replacements)
        return "swift build exited \(status)" + (cleaned.isEmpty ? "" : ": \(cleaned)")
    }

    /// Builds the package and returns what the build left, leaving the
    /// package's `Package.resolved` as it found it. `ranBuild` is called
    /// with the build's task log once the build command has run, whether
    /// it then succeeded or failed: only then did this run write the log.
    func run(ranBuild: (URL) -> Void) throws -> Products {
        let lockfileURL = command.root.appendingPathComponent(CoverageSession.lockfileName)
        let lockfile: PreservedFile
        do {
            lockfile = try PreservedFile(url: lockfileURL)
        } catch {
            throw CoverageFailure(
                description: "could not read \(CoverageSession.lockfileName) to put it back afterwards: "
                    + SwiftInferTargetRun.reason(for: error, replacing: command.replacements)
            )
        }
        ScratchRegistry.shared.preserve(lockfile)
        let built = Result { try describeAndBuild(ranBuild: ranBuild) }
        do {
            try ScratchRegistry.shared.putBack(lockfile)
        } catch {
            throw CoverageFailure(
                description: "could not put \(CoverageSession.lockfileName) back as it was: "
                    + SwiftInferTargetRun.reason(for: error, replacing: command.replacements)
            )
        }
        let described = try built.get()
        let units = command.build.appendingPathComponent(Self.storeDirectory).appendingPathComponent(Self.unitsPath)
        var isDirectory: ObjCBool = false
        let hasStore = FileManager.default.fileExists(atPath: units.path, isDirectory: &isDirectory)
            && isDirectory.boolValue
        return Products(
            toolchain: toolchain,
            scratch: command.build,
            package: described.package,
            modules: described.modules,
            changedFiles: changedFiles(),
            notes: described.notes,
            storeFailure: hasStore
                ? nil
                : "the build wrote no index store at \(CoverageCommand.buildPlaceholder)/\(Self.storeDirectory)"
        )
    }

    /// Describes the package, maps its modules, removes its intermediates
    /// and builds it, calling `ranBuild` as `build(ranBuild:)` does.
    private func describeAndBuild(ranBuild: (URL) -> Void) throws -> Built {
        let package = try describe()
        let modules = try Self.moduleMap(of: package)
        let notes = try removeRootIntermediates(named: package.name)
        try build(ranBuild: ranBuild)
        return Built(package: package, modules: modules, notes: notes)
    }

    /// The package as the toolchain's own `swift package describe` gives
    /// it, with its caches in the build directory; its output is kept in
    /// the build directory as printed.
    private func describe() throws -> DescribedPackage {
        let invocation = ["package", "--scratch-path", command.build.path, "describe", "--type", "json"]
        let display = command.display(toolchain.swift, invocation)
        let output = try command.run(toolchain.swift, invocation, display: display)
        do {
            try output.output.write(to: command.build.appendingPathComponent(Self.describeName))
        } catch {
            throw CoverageFailure(
                description: "could not keep the package description: "
                    + SwiftInferTargetRun.reason(for: error, replacing: command.replacements)
            )
        }
        do {
            return try JSONDecoder().decode(DescribedPackage.self, from: output.output)
        } catch {
            let reason = SwiftInferTargetRun.reason(for: error, replacing: command.replacements)
            throw CoverageFailure(
                description: "`\(display)` printed no package description SwiftStats reads: \(reason)"
            )
        }
    }

    /// Removes the root package's intermediates, `out/Intermediates.noindex/<name>.build`;
    /// a note when the store's directory exists without them.
    private func removeRootIntermediates(named name: String) throws -> [String] {
        let fileManager = FileManager.default
        let out = command.build.appendingPathComponent(Self.storeDirectory)
        let folderName = "\(name).\(Self.intermediatesExtension)"
        let folder = out.appendingPathComponent(Self.intermediatesDirectory).appendingPathComponent(folderName)
        guard fileManager.fileExists(atPath: folder.path) else {
            return fileManager.fileExists(atPath: out.path)
                ? ["\(Self.incompleteLead): no root intermediates named \(folderName) to remove"]
                : []
        }
        do {
            try fileManager.removeItem(at: folder)
        } catch {
            throw CoverageFailure(
                description: "could not remove the root package's intermediates: "
                    + SwiftInferTargetRun.reason(for: error, replacing: command.replacements)
            )
        }
        return []
    }

    /// Runs the build in the package root, its standard output and
    /// standard error written to the build directory's files, and calls
    /// `ranBuild` with the task log once it has run; a failure unless it
    /// exits 0.
    private func build(ranBuild: (URL) -> Void) throws {
        let arguments = Self.arguments(scratch: command.build.path)
        let log = command.build.appendingPathComponent(Self.logName)
        let stderr = command.build.appendingPathComponent(Self.stderrName)
        let termination: ProcessTermination
        do {
            termination = try ProcessRunner.runToEnd(
                executable: toolchain.swift.path,
                arguments: arguments,
                in: command.root,
                writingOutputTo: log,
                writingErrorTo: stderr
            )
        } catch {
            let display = command.display(toolchain.swift, arguments)
            throw command.launchFailure(display, tool: toolchain.swift, error: error)
        }
        ranBuild(log)
        switch termination {
        case .exited(0):
            return

        case .exited(let status):
            let data = (try? Data(contentsOf: stderr)) ?? Data()
            let text = String(bytes: data, encoding: .utf8) ?? String(bytes: data, encoding: .isoLatin1) ?? ""
            let failure = Self.failureReason(status: status, stderr: text, replacing: command.replacements)
            guard status == Self.usageStatus, text.contains(CoverageSession.buildSystemFlags[0]) else {
                throw CoverageFailure(description: failure)
            }
            throw CoverageFailure(
                description: "this toolchain's swift doesn't accept "
                    + "`\(CoverageSession.buildSystemFlags.joined(separator: " "))`, "
                    + "and the index build needs Swift Build (Swift 6.2 or later): \(failure)"
            )

        case .signalled(let number):
            throw CoverageFailure(description: "swift build ended by \(MutationExit.signalName(number))")
        }
    }

    /// The scanned files whose bytes no longer hash as they did when
    /// parsed (or that can no longer be read), by path, sorted.
    private func changedFiles() -> [String] {
        files.filter { file in
            ContentHash.sha256(ofFileAt: command.root.appendingPathComponent(file.path)) != file.sha256
        }
        .map(\.path)
        .sorted()
    }
}
