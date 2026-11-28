//
//  ConfigGen.swift
//  SwiftStatsCoreTests
//
//  Configurations for the configuration properties (design §4.1.6). A
//  valid configuration holds some of PRD §10.1's sections, in any order:
//  `excluded` and `generated` (globs, an empty list, or nothing), `store`,
//  `history` (durations up to the longest, the sweep and coupling floors,
//  regular expressions, commit hashes), `signals` (each ranked signal's
//  threshold and each limit-taking signal's limits, uneven clone
//  mutation's `high` above its `low`) and `collectors` (built and unbuilt
//  names; `enabled` in YAML's six spellings, `path` where one is taken,
//  `--skip` pairs or no value for coverage and swiftmutator, swiftmutator's
//  `workers` and `timeout` or no value, and anything as another
//  collector's `options`; half the `collectors` sections drawn are focused
//  on coverage and swiftmutator, both always there with `arguments` and
//  `options`, and `workers` a base-60 number past one digit). The key
//  names are written here from PRD §10.1, not taken from the reader's own
//  lists, so a key the reader forgets is a valid configuration refused.
//  Values come from short lists holding the edges (`1d`, the longest
//  duration, `5e-324`, a million), and YAML 1.1's integer spellings for
//  `workers` (`0x10`, `1:30`, `10:30`). `ConfigGen+Cases` adds flaws and text
//  that isn't a configuration; `ConfigGen+Keys` adds unknown and repeated
//  keys; `ConfigGen+Bounds` draws the styles a bound is written in. Every
//  draw is a list of decisions a pure interpreter turns into a draft, so a
//  shrunk draw is still a valid one, and lists are ordered simplest first.
//

import PropertyBased

/// Generators of configuration drafts.
enum ConfigGen {
    /// Globs `excluded` and `generated` list.
    static let globs = [
        "Sources/Generated", "**/*.generated.swift", "Tests/Fixtures", "./Plugins/", "Sources/A b",
        "Sources/\u{E9}t\u{E9}"
    ]
    /// Store paths.
    static let storePaths = [".swiftstats/stats.sqlite", "stats.sqlite", "/tmp/swiftstats.sqlite", "a b.sqlite"]
    /// Durations: the defaults, a day, a year, and the longest (PRD §10.1).
    static let durations = ["90d", "1d", "14d", "365d", "106751991167300d"]
    /// Sweep thresholds, each at least 1.
    static let bulkFiles = ["30", "1", "100000"]
    /// Coupling floors, each at least 2.
    static let minSupports = ["3", "2", "50"]
    /// Valid regular expressions.
    static let patterns = ["\\bfix\\b", "^hotfix", "bug|defect", "[x-z]+", "(?:revert)"]
    /// Commit hashes, abbreviated and full, either case.
    static let revisions = ["abcdef0", "ABCDEF1234", "0123456789abcdef0123456789abcdef01234567"]
    /// Ranked signals' thresholds, each in (0, 100].
    static let thresholds = ["10", "0.5", "100", "5e-324"]
    /// Limit percents, each in [0, 100].
    static let percents = ["80", "0", "100", "50.5"]
    /// Limit counts, each from 1 to a million.
    static let counts = ["3", "1", "1000000"]
    /// Ratios, each above 0.
    static let ratios = ["0.25", "1", "1e9"]
    /// Uneven clone mutation's `high` and `low`, either absent, the set
    /// one always on the right side of the other's default (80 and 20).
    static let clonePairs: [(high: String?, low: String?)] = [
        (nil, nil), ("90", nil), (nil, "10"), ("80", "20"), ("100", "0"), ("50.5", "50")
    ]
    /// `enabled` spellings YAML reads as booleans.
    static let flags = ["true", "false", "yes", "no", "on", "off", "True"]
    /// Tool paths.
    static let toolPaths = ["tools/bin/tool", "/usr/local/bin/tool"]
    /// `--skip` regular expressions.
    static let skipPatterns = ["Slow", "a b", "^Live.*$", "(?i)flaky"]
    /// swiftmutator's `workers`, as YAML 1.1 integers.
    static let workerCounts = ["4", "1", "0x10", "1:30", "10:30", "1_0:30"]
    /// Base-60 `workers` whose first place has two digits (630), which a
    /// focused `collectors` section gives swiftmutator.
    static let wideBaseSixty = ["10:30", "1_0:30"]
    /// swiftmutator's `timeout`, in seconds.
    static let timeouts = ["30", "0.25", "86400", "1:30"]
    /// Other collectors' `options`, accepted with a warning whatever they
    /// hold.
    static let otherOptions: [YAMLDraft] = [
        .sequence([.text("--strict")]), .mapping([YAMLDraft.member("level", .text("2"))]), .text("x")
    ]
    /// The collectors SwiftStats runs (PRD §10.1), then two it doesn't,
    /// which are accepted with a warning.
    static let collectorNames = [
        "swiftlint", "coverage", "swiftmutator", "build", "index", "periphery", "dependencies", "swiftprojectlint",
        "swifteffectinference", "swiftinferproperties", "swiftclonedetector", "jazzy", "sourcery"
    ]
    /// The collectors that take no `path`.
    static let pathless: Set<String> = ["build", "index", "swifteffectinference"]
    /// The collectors that take `arguments`.
    static let argumentTaking: Set<String> = ["coverage", "swiftmutator"]
    /// The collector whose `options` hold `workers` and `timeout`.
    static let mutator = "swiftmutator"
    /// The coverage collector.
    static let coverage = "coverage"
    /// The ranked signals.
    static let rankedSignals = ["hotspot", "bug-prone", "clone-hotspot"]
    /// The limit keys drawn independently, each as its signal and limit
    /// and the values drawn from: weak tests', genuinely under-tested's
    /// and hidden coupling's; uneven clone mutation's come from
    /// `clonePairs`.
    static let limitSlots: [(path: [String], values: [String])] = [
        (["weak-tests", "coverage"], percents), (["weak-tests", "score"], percents),
        (["weak-tests", "mutants"], counts),
        (["genuinely-under-tested", "coverage"], percents), (["genuinely-under-tested", "score"], percents),
        (["genuinely-under-tested", "mutants"], counts), (["genuinely-under-tested", "ratio"], ratios),
        (["hidden-coupling", "support"], counts), (["hidden-coupling", "confidence"], percents)
    ]
    /// Uneven clone mutation's signal name.
    static let unevenCloneMutation = "uneven-clone-mutation"

    /// How many globs a list holds.
    static let globCount = 0...3
    /// How many patterns or hashes a list holds.
    static let listCount = 0...2
    /// How many collectors a configuration names, repeats dropped.
    static let collectorCount = 0...4
    /// The largest decision drawn to pick among a few choices; a choice is
    /// taken modulo the choices.
    static let choiceSpread = 11
    /// The share of optional parts present.
    static let presentRate: Float = 0.5
    /// The forms a list takes: the list, an empty list, or no value.
    static let listForms = 3
    /// The durations `history` takes.
    static let durationKeys = ["window", "repeat_window", "half_life"]
    /// The pattern lists `history` takes.
    static let patternKeys = ["fix_patterns", "fix_exclude_patterns"]

    /// `store`.
    static let storeMember = Pick.element(of: storePaths).map { YAMLDraft.member("store", .text($0)) }

    /// `history`: each option present or not.
    static let historyMember = zip(
        Pick.element(of: durations).optional(valueRate: presentRate).array(of: durationKeys.count),
        Pick.element(of: bulkFiles).optional(valueRate: presentRate),
        Pick.element(of: minSupports).optional(valueRate: presentRate),
        Pick.element(of: patterns).array(of: listCount).optional(valueRate: presentRate).array(of: patternKeys.count),
        Pick.element(of: revisions).array(of: listCount).optional(valueRate: presentRate),
        Gen<Int>.value(in: 0...choiceSpread)
    )
    .map { drawnDurations, bulk, minSupport, patternLists, hashes, rotation -> YAMLDraft.Member in
        var members = zip(durationKeys, drawnDurations).compactMap { key, duration in
            duration.map { YAMLDraft.member(key, .text($0)) }
        }
        members += bulk.map { [YAMLDraft.member("bulk_files", .text($0))] } ?? []
        members += minSupport.map { floor in
            [YAMLDraft.member("coupling", .mapping([YAMLDraft.member("min_support", .text(floor))]))]
        } ?? []
        members += zip(patternKeys, patternLists).compactMap { key, list in
            list.map { YAMLDraft.member(key, .sequence($0.map(YAMLDraft.text))) }
        }
        members += hashes.map { [YAMLDraft.member("ignore_revs", .sequence($0.map(YAMLDraft.text)))] } ?? []
        return YAMLDraft.member("history", .mapping(rotated(members, by: rotation)))
    }

    /// `signals`: each ranked threshold and each limit present or not.
    static let signalsMember = zip(
        Pick.element(of: thresholds).optional(valueRate: presentRate).array(of: rankedSignals.count),
        Gen<Int>.value(in: 0...choiceSpread).optional(valueRate: presentRate).array(of: limitSlots.count),
        Pick.element(of: Array(clonePairs.indices)),
        Pick.element(of: counts).optional(valueRate: presentRate),
        Gen<Int>.value(in: 0...choiceSpread)
    )
    .map { ranked, limits, pair, cloneMutants, rotation -> YAMLDraft.Member in
        var bySignal: [(String, [YAMLDraft.Member])] = zip(rankedSignals, ranked).compactMap { signal, value in
            value.map { (signal, [YAMLDraft.member("threshold", .text($0))]) }
        }
        for (slot, choice) in zip(limitSlots, limits) {
            guard let choice else {
                continue
            }
            let signal = slot.path[0]
            let member = YAMLDraft.member(slot.path[1], .text(slot.values[choice % slot.values.count]))
            if let index = bySignal.firstIndex(where: { $0.0 == signal }) {
                bySignal[index].1.append(member)
            } else {
                bySignal.append((signal, [member]))
            }
        }
        let clone = clonePairs[pair]
        let cloneMembers = [("high", clone.high), ("low", clone.low), ("mutants", cloneMutants)]
            .compactMap { key, value in value.map { YAMLDraft.member(key, .text($0)) } }
        if cloneMembers.isEmpty == false {
            bySignal.append((unevenCloneMutation, cloneMembers))
        }
        let members = bySignal.map { YAMLDraft.member($0.0, .mapping($0.1)) }
        return YAMLDraft.member("signals", .mapping(rotated(members, by: rotation)))
    }

    /// One collector's decisions: its form (no value, an empty mapping, or
    /// a mapping), `enabled`, `path`, `--skip` patterns, whether it has
    /// `options` (and which, for a collector other than swiftmutator), and
    /// swiftmutator's `workers` and `timeout`, each present or not.
    static let collectorDecision = zip(
        Gen<Int>.value(in: 0...choiceSpread),
        Pick.element(of: flags).optional(valueRate: presentRate),
        Pick.element(of: toolPaths).optional(valueRate: presentRate),
        Gen.bool(presentRate),
        Pick.element(of: skipPatterns).array(of: listCount),
        Gen<Int>.value(in: 0...choiceSpread).optional(valueRate: presentRate),
        Pick.element(of: workerCounts).optional(valueRate: presentRate),
        Pick.element(of: timeouts).optional(valueRate: presentRate)
    )
    .map { form, enabled, path, hasArguments, skips, options, workers, timeout in
        CollectorDecision(
            form: form,
            enabled: enabled,
            path: path,
            hasArguments: hasArguments,
            skips: skips,
            options: options,
            workers: workers,
            timeout: timeout
        )
    }

    /// `collectors`: up to four names, a repeated one dropped, each with
    /// its decisions.
    static let collectorsMember = zip(
        Pick.element(of: collectorNames).array(of: collectorCount),
        collectorDecision.array(of: collectorCount.upperBound)
    )
    .map { names, decisions -> YAMLDraft.Member in
        var seen = Set<String>()
        let unique = names.filter { seen.insert($0).inserted }
        let entries = zip(unique, decisions).map { name, decision in
            YAMLDraft.member(name, decision.entry(for: name))
        }
        return YAMLDraft.member("collectors", .mapping(entries))
    }

    /// `collectors` focused on the readers of `arguments` and `options`:
    /// coverage's and swiftmutator's entries mappings, each with
    /// `arguments` (no value half the time) and `options` (swiftmutator's
    /// no value half the time, else `workers` from `wideBaseSixty`), among
    /// the other entries drawn, in a rotated order.
    static let focusedCollectorsMember = zip(
        collectorsMember,
        collectorDecision,
        collectorDecision,
        Pick.element(of: wideBaseSixty),
        Gen<Int>.value(in: 0...choiceSpread)
    )
    .map { drawn, coverageDecision, mutatorDecision, workers, rotation -> YAMLDraft.Member in
        let others = YAMLDraft.members(at: ["collectors"], in: [drawn]).filter { member in
            member.key.keyText.map(argumentTaking.contains) != true
        }
        let focused = [
            YAMLDraft.member(coverage, coverageDecision.focused(workers: nil).entry(for: coverage)),
            YAMLDraft.member(mutator, mutatorDecision.focused(workers: workers).entry(for: mutator))
        ]
        return YAMLDraft.member("collectors", .mapping(rotated(focused + others, by: rotation)))
    }

    /// The `collectors` section: none, drawn, or focused, half the time.
    static let collectorsSection = Gen.frequency(
        (classWeight, Gen.always(YAMLDraft.Member?.none)),
        (classWeight, collectorsMember.map(Optional.some)),
        (literalWeight, focusedCollectorsMember.map(Optional.some))
    )

    /// A valid configuration's top-level members: each section present or
    /// not, in a rotated order.
    static let valid = zip(
        listMember("excluded").optional(valueRate: presentRate),
        listMember("generated").optional(valueRate: presentRate),
        storeMember.optional(valueRate: presentRate),
        historyMember.optional(valueRate: presentRate),
        signalsMember.optional(valueRate: presentRate),
        collectorsSection,
        Gen<Int>.value(in: 0...choiceSpread)
    )
    .map { excluded, generated, store, history, signals, collectors, rotation in
        rotated([excluded, generated, store, history, signals, collectors].compactMap(\.self), by: rotation)
    }

    /// A list form: the list itself, an empty list, or nothing.
    static func listMember(_ key: String) -> Generator<YAMLDraft.Member, AnySequence<Any>> {
        zip(Pick.element(of: globs).array(of: globCount), Gen<Int>.value(in: 0...choiceSpread))
            .map { items, form -> YAMLDraft.Member in
                switch form % listForms {
                case 0:
                    return YAMLDraft.member(key, .sequence(items.map(YAMLDraft.text)))

                case 1:
                    return YAMLDraft.member(key, .sequence([]))

                default:
                    return YAMLDraft.member(key, nil)
                }
            }
            .eraseToAny()
    }

    /// `members` rotated left by `count` modulo their number.
    static func rotated(_ members: [YAMLDraft.Member], by count: Int) -> [YAMLDraft.Member] {
        guard members.isEmpty == false else {
            return members
        }
        let shift = count % members.count
        return Array(members[shift...] + members[..<shift])
    }
}
