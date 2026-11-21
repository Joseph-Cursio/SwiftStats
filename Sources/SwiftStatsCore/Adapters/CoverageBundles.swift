//
//  CoverageBundles.swift
//  SwiftStatsCore
//
//  Which test bundle wrote each signature's profiles (M5), and whether every
//  bundle's processes wrote theirs. A group belongs to a bundle by, in
//  order: its runner, a counted function `<Target>.__SwiftPMGeneratedTestRunner.…`
//  once demangled (the mangler substitutes words a target name shares with
//  the runner's, so the mangled text can't be matched); else its test
//  module, a counted function whose mangled name starts `$s<length><Target>`
//  (the runner runs only in the Swift Testing process, so a group whose
//  Swift Testing process crashed has none); else elimination, one group
//  and one bundle left. A bundle is named by its test target, its module
//  by the target's c99 name, so both rules compare the module name. That
//  holds only for Swift Build's layout, one bundle per test target, which
//  the run asks for (`--build-system swiftbuild`); SwiftPM's native build
//  system makes one `<Package>PackageTests` bundle for every test target,
//  whose counts no test target's tests could be linked to, so a bundle
//  that is no test target of the package fails the run.
//

/// Ties profile groups to test bundles and checks them.
enum CoverageBundles {
    /// The mangled names worth demangling: the runner's, in either of the
    /// mangler's spellings.
    static var runnerPattern: Regex<Substring> {
        /__[aA][0-9]+PMGenerated|__SwiftPMGeneratedTestRunner/
    }
    /// The runner's type, as a demangled name spells it after its module.
    private static let runnerType = ".__SwiftPMGeneratedTestRunner."
    /// The prefix of a Swift mangled name.
    private static let manglingPrefix = "$s"

    /// The functions `groups` ran whose names may be the runner's, sorted
    /// and without duplicates: what to demangle.
    static func runnerCandidates(in groups: [CoverageGroup]) -> [String] {
        Array(Set(groups.flatMap(\.counted).filter { $0.contains(runnerPattern) })).sorted()
    }

    /// The module name SwiftPM gives the target `name` (its c99 name): each
    /// character that can't be in an identifier becomes `_`, and so does a
    /// leading digit. Non-ASCII letters are kept, an approximation of the
    /// C99 Annex D ranges SwiftPM keeps.
    static func moduleName(of name: String) -> String {
        var scalars = name.unicodeScalars.map { scalar -> Unicode.Scalar in
            let kept = scalar.isASCII
                ? scalar.properties.isAlphabetic || ("0"..."9").contains(scalar) || scalar == "_"
                : scalar.properties.isAlphabetic || scalar.properties.numericType == .decimal
            return kept ? scalar : "_"
        }
        if let first = scalars.first, first.properties.numericType == .decimal {
            scalars[0] = "_"
        }
        return String(String.UnicodeScalarView(scalars))
    }

    /// The module of the runner `demangled` names, or nil when it names no
    /// runner.
    static func runnerTarget(in demangled: String) -> String? {
        guard let range = demangled.range(of: runnerType) else {
            return nil
        }
        let before = demangled[..<range.lowerBound]
        let module = before.reversed().prefix { $0.isLetter || $0.isNumber || $0 == "_" }
        return module.isEmpty ? nil : String(module.reversed())
    }

    /// Why `bundles` can't be tied to the package's tests, or nil when each
    /// is one of `testTargets`, by module name.
    static func unknownBundles(_ bundles: [String], testTargets: [String]) -> String? {
        let modules = Set(testTargets.map(moduleName))
        let unknown = bundles.filter { modules.contains(moduleName(of: $0)) == false }.sorted()
        guard let last = unknown.last else {
            return nil
        }
        let named = unknown.count == 1
            ? "\(last).xctest, which is no test target of the package"
            : unknown.dropLast().map { "\($0).xctest" }.joined(separator: ", ")
                + " and \(last).xctest, which are no test targets of the package"
        return "coverage needs Swift Build's test bundles, one per test target, but the build made " + named
    }

    /// The bundle each group belongs to, by signature, among `bundles`;
    /// `demangled` gives the demangled text of each runner candidate. A
    /// bundle two groups claim by one rule goes to neither by it.
    static func owners(
        of groups: [CoverageGroup],
        bundles: [String],
        demangled: [String: String]
    ) -> [String: String] {
        var owners: [String: String] = [:]
        claim(groups, bundles: bundles, owners: &owners) { group, open in
            let modules = Set(group.counted.compactMap { demangled[$0].flatMap(runnerTarget) })
            return open.filter { modules.contains(moduleName(of: $0)) }
        }
        claim(groups, bundles: bundles, owners: &owners) { group, open in
            open.filter { bundle in
                let module = moduleName(of: bundle)
                let prefix = "\(manglingPrefix)\(module.utf8.count)\(module)"
                return group.counted.contains { name in name.drop { $0 == "_" }.hasPrefix(prefix) }
            }
        }
        let unclaimedGroups = groups.filter { owners[$0.signature] == nil }
        let unclaimedBundles = Set(bundles).subtracting(owners.values)
        if unclaimedGroups.count == 1, unclaimedBundles.count == 1, let bundle = unclaimedBundles.first {
            owners[unclaimedGroups[0].signature] = bundle
        }
        return owners
    }

    /// Why the run's profiles can't be used, or nil when each of `bundles`
    /// has a group whose XCTest and Swift Testing processes each wrote a
    /// non-empty profile and every group has a bundle.
    static func problem(groups: [CoverageGroup], owners: [String: String], bundles: [String]) -> String? {
        let unclaimed = groups.filter { owners[$0.signature] == nil }.min { $0.signature < $1.signature }
        if let group = unclaimed {
            if let framework = CoverageProfile.frameworks.first(where: { group.wrote($0) == false }) {
                return "the \(framework) test process with signature \(group.signature) wrote no profile "
                    + "(it crashed or was killed)"
            }
            return "the profiles with signature \(group.signature) could not be tied to a test bundle"
        }
        let byBundle = Dictionary(groups.compactMap { group in owners[group.signature].map { ($0, group) } }) { $1 }
        for bundle in bundles.sorted() {
            let group = byBundle[bundle]
            if let framework = CoverageProfile.frameworks.first(where: { group?.wrote($0) != true }) {
                return "the \(framework) test process for \(bundle) wrote no profile (it crashed or was killed)"
            }
        }
        return nil
    }

    /// Gives each group without an owner the one open bundle `candidates`
    /// finds for it, unless another group finds that bundle too.
    private static func claim(
        _ groups: [CoverageGroup],
        bundles: [String],
        owners: inout [String: String],
        candidates: (CoverageGroup, Set<String>) -> Set<String>
    ) {
        let open = Set(bundles).subtracting(owners.values)
        var claims: [String: [String]] = [:]
        for group in groups where owners[group.signature] == nil {
            let found = candidates(group, open)
            if found.count == 1, let bundle = found.first {
                claims[bundle, default: []].append(group.signature)
            }
        }
        for (bundle, signatures) in claims where signatures.count == 1 {
            owners[signatures[0]] = bundle
        }
    }
}
