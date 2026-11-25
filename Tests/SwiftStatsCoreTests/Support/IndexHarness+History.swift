//
//  IndexHarness+History.swift
//  SwiftStatsCoreTests
//
//  The Index fixture's deterministic history, for hidden coupling (M7,
//  design §8.1, §13 step 9c): before the scan, the copy becomes a git
//  repository with a fixed identity and fixed dates, its first commit
//  the fixture as it is, then commits in the window each changing one or
//  two families by a marker line in their bodies (`_ = <n>`, or for
//  top-level code a `print(<n>)` statement), put in by a family's first
//  change, renumbered by the next and taken out by its last, so the last
//  commit's tree is the fixture's again and every change is a change of
//  that family's body. The pairs: `formatLine` with `index-support`'s
//  `parseLine` (no static dependency: listed), two methods of `Session`
//  and a method of `Ledger` with one of its nested `Index` (sharing or
//  nesting a type), `cycle()` with the `Beta.make()` it calls (a
//  reference), `totalArea` with the `Tile.area()` it reaches through the
//  protocol (a requirement), `unitTile()`, which makes a `Tile`, with
//  `Tile.area()` (a type reference), the top-level code with `welcome()`
//  (no USR), a test with `arrayUse()` (a test family), each changed
//  together in 3 commits, and the two `Array` extension methods, changed
//  together in 3 of their 7 commits each (no static dependency, below the
//  confidence limit). The scan reads that history; nothing else differs
//  from `scan(indexed:check:)`.
//

import Foundation
@testable import SwiftStatsCore

extension IndexHarness {
    /// Where a family of the history changes: a line of its file, after
    /// which its body's marker goes, or before which top-level code's
    /// statement goes.
    struct Changing {
        /// The file, relative to the package root.
        let file: String
        /// The line, whole, as the fixture has it once.
        let anchor: String
        /// Whether it is top-level code, changed by a statement before the
        /// anchor rather than a marker after it.
        let topLevel: Bool
    }

    /// `IndexCore`'s file of `formatLine`.
    private static let formattingFile = "Sources/IndexCore/Formatting.swift"
    /// `IndexCore`'s file of types.
    private static let typesFile = "Sources/IndexCore/Types.swift"
    /// `IndexCore`'s file of protocols.
    private static let protocolsFile = "Sources/IndexCore/Protocols.swift"
    /// `IndexCore`'s file of `Session`.
    private static let lifecycleFile = "Sources/IndexCore/Lifecycle.swift"

    /// The families the history changes, by short name.
    static let changing: [String: Changing] = [
        "formatLine": body(formattingFile, "public func formatLine(_ fields: [String]) -> String {"),
        "parseLine": body("Sources/Kits/Support.swift", "public func parseLine(_ line: String) -> [String] {"),
        "open": body(lifecycleFile, "    public func open() -> String {"),
        "close": body(lifecycleFile, "    public func close() -> String {"),
        "index": body(typesFile, "    func index(at position: Int) -> Index {"),
        "entry": body(typesFile, "        func entry(in ledger: Ledger) -> Int {"),
        "cycle": body(typesFile, "public func cycle() -> Int {"),
        "make": body(typesFile, "    func make() -> Alpha {"),
        "totalArea": body(protocolsFile, "public func totalArea(_ shapes: [any Shape]) -> Int {"),
        "area": body(protocolsFile, "    func area() -> Int {"),
        "unitTile": body(protocolsFile, "public func unitTile() -> any Shape {"),
        "topLevel": Changing(file: "Sources/IndexApp/main.swift", anchor: "print(greeting.count)", topLevel: true),
        "welcome": body(protocolsFile, "public func welcome() -> String {"),
        "writesLevel": body("Tests/IndexCoreTests/IndexCoreTests.swift", "    @Test func writesLevel() {"),
        "arrayUse": body(typesFile, "public func arrayUse() -> Int {"),
        "doubledAll": body(typesFile, "    func doubledAll() -> [Int] {"),
        "secondItem": body(typesFile, "    func secondItem() -> Element? {")
    ]

    /// The pairs changed together, in each round of the history.
    static let coupled = [
        ["formatLine", "parseLine"], ["open", "close"], ["index", "entry"], ["cycle", "make"],
        ["totalArea", "area"], ["unitTile", "area"], ["topLevel", "welcome"], ["writesLevel", "arrayUse"],
        ["doubledAll", "secondItem"]
    ]

    /// The commits in the window, each the families it changes: three
    /// rounds of the coupled pairs, then each `Array` extension method
    /// alone, four times each.
    static let historyCommits: [[String]] = Array(repeating: coupled, count: rounds).flatMap(\.self)
        + Array(repeating: [["doubledAll"], ["secondItem"]], count: aloneChanges).flatMap(\.self)

    /// The rounds of the coupled pairs: each pair's support.
    static let rounds = 3
    /// The commits changing each `Array` extension method alone.
    static let aloneChanges = 4
    /// The day, after day zero, of the history's first commit, outside the
    /// window.
    private static let firstDay = 0
    /// The day before the first commit in the window.
    private static let windowDay = 400
    /// The indentation a body's marker adds to its declaration's.
    private static let indentWidth = 4

    /// A family changed by a marker after `anchor` in `file`.
    private static func body(_ file: String, _ anchor: String) -> Changing {
        Changing(file: file, anchor: anchor, topLevel: false)
    }

    /// Scans a copy of the Index fixture with `--index` and the fake
    /// outskirts answering with the recorded runs, as
    /// `scan(indexed:check:)` does, after giving it the deterministic
    /// history, which the scan reads; passes the scan to `check`.
    static func scanWithHistory(check: (ScannedSnapshot) throws -> Void) async throws {
        let fake = try FakePeriphery.make(try FakePeriphery.recorded())
        defer { fake.remove() }
        var scan = try IndexFixtureScan()
        scan.extra = fake.configuration
        scan.prepare = { fixture in
            try makeHistory(at: URL(fileURLWithPath: fixture.root))
        }
        scan.history = { fixture in
            let root = URL(fileURLWithPath: fixture.root)
            return .commit(top: root, commit: try git(["rev-parse", "HEAD"], in: root, day: nil), packagePath: "")
        }
        try await scan.run { _, outcome in
            try check(outcome.snapshot)
        }
    }

    /// Makes the package at `root` a git repository holding the history,
    /// its last commit's tree the package as it is.
    static func makeHistory(at root: URL) throws {
        let originals = try Dictionary(Set(changing.values.map(\.file)).map { file in
            (file, try String(contentsOf: root.appendingPathComponent(file), encoding: .utf8))
        }) { first, _ in first }
        try git(["init", "-q", "-b", "main"], in: root, day: nil)
        try commit("The fixture", in: root, day: firstDay)
        var remaining = historyCommits.flatMap(\.self).reduce(into: [String: Int]()) { $0[$1, default: 0] += 1 }
        var markers: [String: Int] = [:]
        for (offset, families) in historyCommits.enumerated() {
            let number = offset + 1
            for family in families {
                remaining[family, default: 0] -= 1
                markers[family] = remaining[family] == 0 ? nil : number
            }
            for (file, text) in originals {
                try marked(text, file: file, markers: markers)
                    .write(to: root.appendingPathComponent(file), atomically: true, encoding: .utf8)
            }
            try commit("Change " + families.joined(separator: " and "), in: root, day: windowDay + number)
        }
    }

    /// `text`, the fixture's `file`, with a marker numbered `markers[name]`
    /// for each family of the file holding one.
    private static func marked(_ text: String, file: String, markers: [String: Int]) throws -> String {
        var lines = text.components(separatedBy: "\n")
        for (name, number) in markers.sorted(by: { $0.key < $1.key }) {
            guard let place = changing[name], place.file == file else {
                continue
            }
            guard let position = lines.firstIndex(of: place.anchor) else {
                throw IndexFixtureScanError(description: "\(file) has no line \(place.anchor)")
            }
            if place.topLevel {
                lines.insert("print(\(number))", at: position)
            } else {
                let indent = place.anchor.prefix { $0 == " " }.count + indentWidth
                lines.insert(String(repeating: " ", count: indent) + "_ = \(number)", at: position + 1)
            }
        }
        return lines.joined(separator: "\n")
    }

    /// Commits everything in `root` with `message`, dated `day` days after
    /// day zero.
    private static func commit(_ message: String, in root: URL, day: Int) throws {
        try git(["add", "-A"], in: root, day: nil)
        try git(["commit", "-q", "-m", message], in: root, day: day)
    }

    /// Runs git in `root` with a fixed identity, dated `day` days after
    /// day zero when given, and gives its output trimmed.
    @discardableResult
    private static func git(_ arguments: [String], in root: URL, day: Int?) throws -> String {
        let identity = [
            "-c", "user.name=SwiftStats Tests", "-c", "user.email=tests@example.invalid", "-c", "commit.gpgsign=false"
        ]
        let data = try ProcessRunner.run(
            executable: "/usr/bin/git",
            arguments: identity + arguments,
            in: root,
            environment: day.map(HistoryRepository.dated) ?? [:]
        )
        return (String(bytes: data, encoding: .utf8) ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
    }
}
