//
//  TestNameMatcher.swift
//  SwiftStatsCore
//
//  Finds a production family's tests by file name until coverage can say
//  which tests run it (PRD §7.13, M5). Names are compared in tiers, and the
//  first tier that finds anything wins: the test named for the file, then
//  tests named for the file plus a topic (`FunctionScannerBodyTests` for
//  `FunctionScanner.swift`), then tests named for the enclosing type.
//

/// Matches production families to test files by name.
struct TestNameMatcher {
    /// The test name of every test file: its base name without `.swift` and
    /// a trailing `Tests`, `Test` or `Spec`.
    private let testNames: Set<String>

    /// A matcher over the test files at `paths`.
    init(testFiles paths: [String]) {
        testNames = Set(paths.map(Self.testName(of:)))
    }

    /// The test name of the test file at `path`.
    static func testName(of path: String) -> String {
        var name = baseName(path)
        for suffix in ["Tests", "Test", "Spec"] where name.hasSuffix(suffix) && name.count > suffix.count {
            name.removeLast(suffix.count)
            break
        }
        return name
    }

    /// Whether `name` is `stem` followed by a capitalised topic.
    private static func isTopic(_ name: String, of stem: String) -> Bool {
        guard stem.isEmpty == false, name.hasPrefix(stem), name.count > stem.count else {
            return false
        }
        return name[name.index(name.startIndex, offsetBy: stem.count)].isUppercase
    }

    /// `path`'s last component without `.swift`.
    private static func baseName(_ path: String) -> String {
        let last = path.split(separator: "/").last.map(String.init) ?? path
        return last.hasSuffix(".swift") ? String(last.dropLast(".swift".count)) : last
    }

    /// The enclosing type named in a family id (`Module::Type::func f()`),
    /// nil for a free function. A type path keeps its last component.
    static func typeName(of familyID: String) -> String? {
        let core = HistoryMatcher.stripModule(familyID)
        guard let range = core.range(of: "::", options: .backwards) else {
            return nil
        }
        let path = core[..<range.lowerBound]
        let last = path.split(separator: ".").last.map(String.init) ?? String(path)
        return last.split(separator: " ").first.map(String.init)
    }

    /// The test names matching a family in the file at `path` whose
    /// enclosing type is `typeName`.
    func matches(file path: String, typeName: String?) -> Set<String> {
        let base = Self.baseName(path)
        let normalised = base.filter { $0 != "+" && $0 != "." }
        let head = String(base.prefix { $0 != "+" && $0 != "." })
        let exact = testNames.intersection([normalised, head].filter { $0.isEmpty == false })
        if exact.isEmpty == false {
            return exact
        }
        let topical = testNames.filter { Self.isTopic($0, of: normalised) }
        if topical.isEmpty == false {
            return topical
        }
        guard let typeName, typeName.isEmpty == false else {
            return []
        }
        return testNames.filter { $0 == typeName || Self.isTopic($0, of: typeName) }
    }
}
