//
//  PeripheryOutput.swift
//  SwiftStatsCore
//
//  outskirts' two runs read (M7, design §5.3). Each run's standard output
//  is a JSON array (`[]` when nothing is found) whose every entry holds
//  the nine keys `accessibility`, `attributes`, `hints`, `ids`, `kind`,
//  `location`, `modifiers`, `modules` and `name`; extra keys (`asset`, a
//  later release's `range`) are ignored. An entry lacking a key, a value of
//  another type, a `hints` list without exactly one hint or a location
//  that isn't `path:line:column` is a format failure the collector reports
//  naming outskirts' version and hash. A hint written `name(text)` is read
//  as the name with the text kept. A location is read from the right, its
//  path made real (NFC) and looked up among the scanned files' real paths,
//  then the describe's other sources' (`SourcePaths`): a scanned file's
//  spelling, else a source's manifest spelling, else, under the package
//  root, a path in the package. Modules, C99 names in the JSON, become
//  target names wherever they are the package's (design choice 5). Each
//  entry then gets its class (`PeripheryEntryClass`), the first that
//  applies. An entry is test code when the target the scan reads its
//  file in is a test target (Package.swift's test targets, never folders:
//  a production target sharing a test target's directory stays
//  production); only a file the scan didn't parse falls back to lying in
//  a test target's directory, or every `modules` entry being a test
//  target. A local
//  variable is told by the index, when it ran (its USR's definition has
//  the local property), or by its place: a variable kind, a parameter
//  aside, lying in a record other than top-level code, where no global
//  can be declared. Only variables are classed local: a local function is
//  a record of its own, and a local type owns records, so both stay
//  production code for the mapping.
//

import Foundation

/// The entries of outskirts' two runs, read and classed.
struct PeripheryOutput: Sendable {
    /// What classing an entry needs from the scan and the build.
    struct Context: Sendable {
        /// The package root's real path, NFC.
        let root: String
        /// The build directory's real path, NFC.
        let scratch: String
        /// The package as the T1 describe gives it.
        let package: DescribedPackage
        /// Each target's C99 module name, mapped to the target's name.
        let modules: [String: String]
        /// The scanned files, as paths in the package, each to the target
        /// the scan reads it in.
        let files: [String: String]
        /// The scanned files that changed during the scan.
        let changedFiles: Set<String>
        /// The scan's records.
        let records: [FunctionRecord]
        /// The USRs whose definitions the index marks local; empty when
        /// the index didn't run.
        let localUSRs: Set<String>

        /// The test targets' names.
        var testTargets: Set<String> {
            Set(package.targets.filter { $0.type == PeripheryOutput.testType }.map(\.name))
        }

        /// The scanned files, then the describe's other sources, by real
        /// path.
        var paths: SourcePaths {
            SourcePaths(
                root: root,
                sources: files.map { SourcePaths.Source(path: $0.key, target: $0.value) },
                fallback: SourcePaths.sources(of: package)
            )
        }

        /// The test targets' directories, as paths in the package.
        var testDirectories: [String] {
            package.targets.filter { $0.type == PeripheryOutput.testType }.map { target in
                TargetResolver.normalised(target.path).precomposedStringWithCanonicalMapping
            }
        }
    }

    /// An output that doesn't read as design §5.3 describes it.
    struct FormatFailure: Error, CustomStringConvertible {
        /// What is wrong, after outskirts' version and hash.
        let description: String
    }

    /// The rule the entries are classed by, the collector's `classes:`
    /// option.
    static let rule = "build, outside the root, test targets (the scanned file's target; an unscanned file's "
        + "test directory or modules), unscanned, files changed during the scan, "
        + "local variables (a variable kind other than a parameter whose USR the index marks local, or lying "
        + "in a record other than top-level code), else production"
    /// The keys every entry holds.
    static let keys = [
        "accessibility", "attributes", "hints", "ids", "kind", "location", "modifiers", "modules", "name"
    ]
    /// The keys whose values are lists of strings.
    private static let listKeys: Set = ["attributes", "hints", "ids", "modifiers", "modules"]
    /// A test target's type in the describe.
    static let testType = "test"
    /// What a variable's kind starts with.
    private static let variablePrefix = "var."
    /// A parameter's kind: it lies in its function's signature.
    private static let parameterKind = "var.parameter"

    /// outskirts' version, as `outskirts version` printed it.
    let version: String
    /// The library-product targets whose public declarations were
    /// retained, in code point order.
    let retained: [String]
    /// The entries of the `roots` run, then those of the `production`
    /// run, each in its output's order.
    let entries: [PeripheryEntry]

    /// The entries of `run`'s output `data`, classed with `context`; a
    /// `FormatFailure` when it isn't an array of entries as design §5.3
    /// describes them.
    static func decode(_ data: Data, run: PeripheryCommand.Run, context: Context) throws -> [PeripheryEntry] {
        let object: Any
        do {
            object = try JSONSerialization.jsonObject(with: data)
        } catch {
            throw FormatFailure(
                description: "JSON doesn't decode in the \(run.rawValue) run: \(error.localizedDescription)"
            )
        }
        guard let array = object as? [Any] else {
            throw FormatFailure(description: "JSON isn't an array in the \(run.rawValue) run")
        }
        let byFile = Dictionary(grouping: context.records, by: \.file)
        let paths = context.paths
        return try array.enumerated().map { offset, element in
            let entry = try fields(of: element, ordinal: offset + 1, run: run)
            let path = IndexStoreReader.realPath(entry.location.path)
            let modules = entry.lists["modules", default: []].map { context.modules[$0] ?? $0 }
            let file = paths.packagePath(of: path, in: modules.first)
            let (hint, hintText) = split(entry.lists["hints", default: []][0])
            let draft = PeripheryEntry(
                run: run,
                ordinal: offset + 1,
                hint: hint,
                hintText: hintText,
                kind: entry.strings["kind", default: ""],
                name: entry.strings["name", default: ""],
                accessibility: entry.strings["accessibility", default: ""],
                attributes: entry.lists["attributes", default: []],
                modifiers: entry.lists["modifiers", default: []],
                ids: entry.lists["ids", default: []],
                modules: modules,
                path: path,
                file: file,
                line: entry.location.line,
                column: entry.location.column,
                entryClass: .production
            )
            return draft.classed(entryClass(of: draft, context: context, records: byFile[file ?? ""] ?? []))
        }
    }

    /// The class of `entry`, the first that applies, with `context` and
    /// `records`, the scan's records of its file.
    static func entryClass(
        of entry: PeripheryEntry,
        context: Context,
        records: [FunctionRecord]
    ) -> PeripheryEntryClass {
        if entry.path == context.scratch || entry.path.hasPrefix(context.scratch + "/") {
            return .build
        }
        guard let file = entry.file else {
            return .outsideRoot
        }
        let testTargets = context.testTargets
        guard let target = context.files[file] else {
            let inTestDirectory = context.testDirectories.contains { file.hasPrefix($0 + "/") }
            if inTestDirectory || (entry.modules.isEmpty == false && entry.modules.allSatisfy(testTargets.contains)) {
                return .test
            }
            return .unscanned
        }
        if testTargets.contains(target) {
            return .test
        }
        if context.changedFiles.contains(file) {
            return .fileChanged
        }
        return isLocal(entry, localUSRs: context.localUSRs, records: records) ? .local : .production
    }

    /// Whether `entry` is a local variable: a variable kind other than a
    /// parameter whose USR is among `localUSRs` (empty when the index
    /// didn't run), or that lies in one of its file's `records` other
    /// than top-level code.
    private static func isLocal(_ entry: PeripheryEntry, localUSRs: Set<String>, records: [FunctionRecord]) -> Bool {
        guard entry.kind.hasPrefix(variablePrefix), entry.kind != parameterKind else {
            return false
        }
        if entry.ids.contains(where: localUSRs.contains) {
            return true
        }
        let position = SourcePosition(line: entry.line, column: entry.column)
        guard let holder = USRJoin.innermost(of: records, holding: position) else {
            return false
        }
        return holder.kind != .topLevelCode
    }

    /// `hint` split into its name and the text in its parentheses, when it
    /// is written `name(text)`; else the hint and nil.
    private static func split(_ hint: String) -> (String, String?) {
        guard hint.hasSuffix(")"), let open = hint.firstIndex(of: "(") else {
            return (hint, nil)
        }
        let name = hint[..<open]
        guard name.isEmpty == false, name.allSatisfy({ $0.isASCII && $0.isLetter }) else {
            return (hint, nil)
        }
        return (String(name), String(hint[hint.index(after: open)..<hint.index(before: hint.endIndex)]))
    }

    /// The nine fields of `element`, the `ordinal`th entry of `run`'s
    /// output, checked; a `FormatFailure` naming the first that is missing
    /// or of another type.
    private static func fields(of element: Any, ordinal: Int, run: PeripheryCommand.Run) throws -> PeripheryFields {
        let place = "in entry \(ordinal) of the \(run.rawValue) run"
        guard let object = element as? [String: Any] else {
            throw FormatFailure(description: "JSON has an entry that isn't an object \(place)")
        }
        var fields = PeripheryFields()
        for key in keys {
            guard let value = object[key] else {
                throw FormatFailure(description: "JSON lacks \"\(key)\" \(place)")
            }
            if listKeys.contains(key) {
                guard let list = value as? [Any], let strings = list as? [String] else {
                    throw FormatFailure(description: "JSON's \"\(key)\" isn't a list of strings \(place)")
                }
                fields.lists[key] = strings
            } else {
                guard let string = value as? String else {
                    throw FormatFailure(description: "JSON's \"\(key)\" isn't a string \(place)")
                }
                fields.strings[key] = string
            }
        }
        let hints = fields.lists["hints", default: []]
        guard hints.count == 1 else {
            throw FormatFailure(description: "JSON's \"hints\" holds \(hints.count) hints, not one, \(place)")
        }
        guard let location = PeripheryFields.Location(fields.strings["location", default: ""]) else {
            throw FormatFailure(description: "JSON's \"location\" isn't path:line:column \(place)")
        }
        fields.location = location
        return fields
    }

    /// `run`'s entries in its output's order.
    func entries(of run: PeripheryCommand.Run) -> [PeripheryEntry] {
        entries.filter { $0.run == run }
    }
}
