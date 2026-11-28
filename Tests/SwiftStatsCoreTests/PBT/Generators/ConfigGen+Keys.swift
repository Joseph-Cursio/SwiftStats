//
//  ConfigGen+Keys.swift
//  SwiftStatsCoreTests
//
//  Key faults for P11.3: at one level of a valid configuration (the top,
//  `history`, `history.coupling`, `signals`, a ranked signal, two
//  limit-taking signals, a built and an unbuilt collector's entry,
//  swiftmutator's `options`, and the collector names; the top level most,
//  where the reader's own repeat check lies), one or two unknown
//  keys (near misses of known ones, an accented word, a space, a colon, a
//  leading `-` or `#`, a merge key, and the words plain YAML reads as an
//  integer or a boolean), or one key written twice: a known key of that
//  level, or a word plain YAML reads as another type, each time plain,
//  single- or double-quoted. Unknown collector names are accepted with a
//  warning (PRD §10.1), so the collector names only take repeats. The
//  known keys of each level are written here from PRD §10.1.
//

import PropertyBased

/// Generators of key faults.
extension ConfigGen {
    /// The keys PRD §10.1 gives `history`.
    static let historyKeys = [
        "window", "fix_patterns", "fix_exclude_patterns", "repeat_window", "half_life", "bulk_files", "ignore_revs",
        "coupling"
    ]
    /// The signals PRD §8 and §10.1 configure.
    static let signalNames = [
        "hotspot", "bug-prone", "clone-hotspot", "weak-tests", "genuinely-under-tested", "uneven-clone-mutation",
        "hidden-coupling"
    ]
    /// The levels a fault goes in, and the keys PRD §10.1 gives each.
    static let keyLevels: [(path: [String], known: [String])] = [
        ([], ["excluded", "generated", "collectors", "store", "history", "signals"]),
        (["history"], historyKeys),
        (["history", "coupling"], ["min_support"]),
        (["signals"], signalNames),
        (["signals", "hotspot"], ["threshold"]),
        (["signals", "genuinely-under-tested"], ["coverage", "score", "mutants", "ratio"]),
        (["signals", "uneven-clone-mutation"], ["high", "low", "mutants"]),
        (["collectors", "swiftlint"], ["enabled", "path", "options"]),
        (["collectors", "jazzy"], ["enabled", "path", "options"]),
        (["collectors", "swiftmutator", "options"], ["workers", "timeout"]),
        (["collectors"], collectorNames)
    ]
    /// The levels a fault is drawn at, by index into `keyLevels`: the top
    /// level three times, since only there does the reader itself refuse
    /// a repeat (of a key YAML reads as two types: Yams refuses the rest),
    /// and that repeat came in 3 faults of 1,000 when every level was
    /// drawn alike (step 14's first meta-test).
    static let levelChoices = [0, 0] + Array(keyLevels.indices)
    /// The level whose unknown keys are accepted: the collector names.
    static let namesLevel = ["collectors"]
    /// Keys no level knows, distinct even compared canonically.
    static let unknownNames = [
        "exclude", "Excluded", "stores", "histroy", "windows", "thresholds", "enable", "paths", "Workers", "time_out",
        "caf\u{E9}", "a b", "x:y", "-x", "#x", "<<", "1", "true"
    ]
    /// How a key is written.
    static let quotes: [YAMLDraft.Quote] = [.plain, .single, .double]
    /// How many unknown keys a fault puts in.
    static let unknownCount = 1...2
    /// The share of faults that repeat a key.
    static let duplicateRate: Float = 0.5

    /// A key fault at a level.
    static let keyFault = zip(
        Pick.element(of: levelChoices),
        Gen.bool(duplicateRate),
        Pick.element(of: unknownNames).array(of: unknownCount),
        Pick.element(of: quotes).array(of: unknownCount),
        Gen<Int>.value(in: 0...choiceSpread),
        Pick.element(of: quotes),
        Pick.element(of: quotes),
        Gen<Int>.value(in: 0...choiceSpread)
    )
    .map { levelIndex, repeats, names, nameQuotes, keyChoice, firstQuote, secondQuote, position in
        let level = keyLevels[levelIndex]
        guard repeats || level.path == namesLevel else {
            var seen = Set<String>()
            let keys = zip(names, nameQuotes + nameQuotes).compactMap { name, quote -> YAMLDraft? in
                seen.insert(name).inserted ? keyScalar(name, quote: quote) : nil
            }
            return KeyFault(level: level.path, kind: .unknown(keys), position: position)
        }
        // The words YAML reads as two types are listed twice, so a repeat
        // takes one about two times in five.
        let typed = KeyFault.typedKeys.sorted()
        let candidates = level.path == namesLevel ? level.known : level.known + typed + typed
        let key = candidates[keyChoice % candidates.count]
        let first = quote(firstQuote, for: key)
        let second = quote(secondQuote, for: key)
        return KeyFault(level: level.path, kind: .duplicate(key: key, first: first, second: second), position: position)
    }

    /// A configuration holding a key fault, laid out.
    static let keyFaultCase = zip(valid, keyFault, layout)
        .map { members, fault, layout in KeyFaultCase(members: members, fault: fault, layout: layout) }

    /// `text` as a key written as `quote` says, double-quoted when it
    /// can't be written plain.
    static func keyScalar(_ text: String, quote: YAMLDraft.Quote) -> YAMLDraft {
        .scalar(text, Self.quote(quote, for: text))
    }

    /// `quote`, or double quotes when `quote` is plain and `text` can't be
    /// written plain.
    static func quote(_ quote: YAMLDraft.Quote, for text: String) -> YAMLDraft.Quote {
        quote == .plain && YAMLText.isPlainSafe(text) == false ? .double : quote
    }
}
