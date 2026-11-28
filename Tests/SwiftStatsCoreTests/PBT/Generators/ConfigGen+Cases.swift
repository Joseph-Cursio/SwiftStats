//
//  ConfigGen+Cases.swift
//  SwiftStatsCoreTests
//
//  P11.1's inputs: "parsing any YAML text" (design §4.1.6), from all of
//  the generator's branches. A valid configuration, laid out in block or
//  flow style, after a document start, a comment or a version directive,
//  with `\n` or `\r\n` line ends; an empty one after a document start,
//  which YAML reads as a null document (PRD §10.1 makes every section
//  optional); the same with one flaw put in (`ConfigFlaw`); or text that
//  isn't a configuration, a run of YAML's syntax, the configuration's
//  words and any text fragment. An
//  odd spelling goes at swiftmutator's `workers` half the time, and a
//  third of spellings are base-60 numbers whose places, a place's value
//  or its sign pass `Int`, since Yams' base-60 reading trapped on those
//  (design B30): about one draw in twenty-five puts one at `workers`.
//

import PropertyBased

/// Generators of any configuration text.
extension ConfigGen {
    /// Which branch a text comes from.
    enum Branch: Sendable {
        /// A valid configuration with no members, after a document start.
        case empty
        /// A valid configuration with a flaw put in.
        case flawed
        /// Text that isn't a configuration.
        case soup
        /// A valid configuration.
        case valid
    }

    /// A depth past the deepest mapping (swiftmutator's `options`, three
    /// levels down): block style throughout.
    static let blockDepth = 4
    /// What may come before the first key: a document start, a comment, a
    /// version directive. Never a byte order mark: `load` reads the file
    /// through `String(contentsOf:encoding:)`, which drops a leading one,
    /// so `parse` never sees it (step 14's probe; Yams, told the text is
    /// UTF-8, would read the mark as a character and the first key one
    /// column in).
    static let prefixes = ["---\n", "# .swiftstats.yml\n", "%YAML 1.1\n---\n"]
    /// The share of texts whose lines end in `\r\n`.
    static let crlfRate: Float = 0.25
    /// The top-level keys.
    static let topKeys = ["excluded", "generated", "store", "history", "signals", "collectors"]
    /// swiftmutator's `workers`.
    static let workersPath = ["collectors", "swiftmutator", "options", "workers"]
    /// Paths of scalar values a spelling flaw writes over.
    static let valuePaths: [[String]] = [
        ["store"], ["history", "window"], ["history", "repeat_window"], ["history", "half_life"],
        ["history", "bulk_files"], ["history", "coupling", "min_support"], ["signals", "hotspot", "threshold"],
        ["signals", "bug-prone", "threshold"], ["signals", "clone-hotspot", "threshold"],
        ["signals", "weak-tests", "coverage"], ["signals", "weak-tests", "mutants"],
        ["signals", "genuinely-under-tested", "ratio"], ["signals", "uneven-clone-mutation", "high"],
        ["signals", "hidden-coupling", "support"], workersPath, ["collectors", "swiftmutator", "options", "timeout"],
        ["collectors", "swiftlint", "enabled"], ["collectors", "coverage", "path"]
    ]
    /// Odd spellings of a value: out of range, YAML 1.1 integers, special
    /// floats, numbers past `Int`, a fullwidth digit, quoted numbers,
    /// tags, an anchor, null, an empty string, a boolean, empty
    /// collections.
    static let oddSpellings = [
        "0", "-1", "-0", "0d", "+5", "0x10", "010", "08", "1_0", "1:30", ".inf", "-.inf", ".nan", "nan", "inf", "1e400",
        "99999999999999999999", "\u{FF11}", "100.00000000000001", "-5e-324", "1000001", "106751991167301d", "\"4\"",
        "'30d'", "!!str 4", "!!int 4", "!!float 1", "!!binary aGk=", "&n 5", "~", "\"\"", "true", "[]", "{}"
    ]
    /// Base-60 numbers past `Int`, each trapping Yams' reading: eleven
    /// places (the place value after the last passes it), twelve (the last
    /// place's value passes it), a place too large, and a sum that is
    /// `Int.min`, negated.
    static let baseSixtyTraps = [
        "1:0:0:0:0:0:0:0:0:0:0", "1:0:0:0:0:0:0:0:0:0:0:0", "9223372036854775807:0", "153722867280912931:0",
        "--153722867280912930:-8", "-9223372036854775807:59"
    ]
    /// Paths a node of another type goes at: sections, nested mappings,
    /// lists, and scalar values.
    static let typePaths: [[String]] = [
        ["excluded"], ["generated"], ["store"], ["history"], ["signals"], ["collectors"], ["history", "coupling"],
        ["history", "ignore_revs"], ["signals", "hotspot"], ["collectors", "swiftlint"],
        ["collectors", "swiftmutator", "options"], ["collectors", "coverage", "arguments"], ["history", "window"],
        ["collectors", "swiftlint", "enabled"]
    ]
    /// The `arguments` lists a flaw goes at.
    static let argumentPaths = [["collectors", "coverage", "arguments"], ["collectors", "swiftmutator", "arguments"]]
    /// `arguments` lists that aren't `--skip <regex>` pairs: a `--skip`
    /// with no regex, alone or after a pair; an empty regex; another flag;
    /// a regex that is a flag.
    static let argumentFlaws = [["--skip"], ["--skip", "a", "--skip"], ["--skip", ""], ["-x"], ["--skip", "-x"]]
    /// Nodes of another type: none, a sequence, a mapping, a scalar, and
    /// an empty sequence.
    static let otherTypes: [YAMLDraft?] = [
        nil, .sequence([.text("a")]), .mapping([YAMLDraft.member("a", .text("b"))]), .text("text"), .sequence([])
    ]
    /// The forms of a key that isn't plain text, about a known key `k`:
    /// tagged `!t k`, `!!str k` (a string, so `k` itself) and `!!binary k`,
    /// a sequence `[k]`, a mapping `{k: x}`, a merge key, an alias, and an
    /// anchored `k` (`k` itself).
    static let exoticForms: [@Sendable (String) -> String] = [
        { "!t " + $0 }, { "!!str " + $0 }, { "!!binary " + $0 }, { "[" + $0 + "]" }, { "{" + $0 + ": x}" },
        { _ in "<<" }, { _ in "*" + ConfigFlaw.anchorName }, { "&k " + $0 }
    ]
    /// How many fragments text that isn't a configuration has.
    static let soupLength = 0...40
    /// The fragments it is made of: YAML's syntax, the configuration's
    /// words, and values.
    static let soupTokens = [
        "excluded", "history", "window", "signals", "collectors", "swiftmutator", "options", "workers", ":", ": ", " ",
        "\n", "  ", "- ", "[", "]", "{", "}", ", ", "\"", "'", "#", "&a ", "*a", "!t ", "!!int ", "|", ">", "---",
        "...", "%YAML 1.1", "? ", "\t", "\r\n", "1:30", "0x10", "~", "<<", "1d", "1:0:0:0:0:0:0:0:0:0:0"
    ]

    /// Weight of the plainest choice.
    static let plainWeight = 3.0
    /// Weight of a common choice.
    static let commonWeight = 3.0
    /// Weight of a literal choice.
    static let literalWeight = 2.0
    /// Weight of each other class.
    static let classWeight = 1.0
    /// Weight of a rare class.
    static let rareWeight = 0.5

    /// A layout: block style mostly, else from any depth; nothing before
    /// the first key mostly; `\r\n` sometimes.
    static let layout = zip(
        Gen.frequency((plainWeight, Gen.always(blockDepth)), (classWeight, Gen<Int>.value(in: 0...blockDepth))),
        Gen.frequency((plainWeight, Gen.always("")), (classWeight, Pick.element(of: prefixes))),
        Gen.bool(crlfRate)
    )
    .map { depth, prefix, crlf in ConfigLayout(flowDepth: depth, prefix: prefix, endsInCRLF: crlf) }

    /// A value spelled oddly, half the time at `workers`.
    static let spelling = zip(
        Gen.frequency((classWeight, Gen.always(workersPath)), (classWeight, Pick.element(of: valuePaths))),
        Gen.frequency((classWeight, Pick.element(of: baseSixtyTraps)), (literalWeight, Pick.element(of: oddSpellings)))
    )
    .map { path, text in ConfigFlaw.spelling(path: path, text: text) }

    /// A node of another type at a path.
    static let wrongType = zip(Pick.element(of: typePaths), Pick.element(of: otherTypes))
        .map { path, value in ConfigFlaw.wrongType(path: path, value: value) }

    /// An `arguments` list that isn't `--skip <regex>` pairs.
    static let badArguments = zip(Pick.element(of: argumentPaths), Pick.element(of: argumentFlaws))
        .map { path, tokens in ConfigFlaw.arguments(path: path, tokens: tokens) }

    /// A key that isn't plain text, at a level.
    static let exoticKey = zip(
        Pick.element(of: Array(keyLevels.indices)),
        Gen<Int>.value(in: 0...choiceSpread),
        Gen<Int>.value(in: 0...choiceSpread),
        Gen<Int>.value(in: 0...choiceSpread)
    )
    .map { levelIndex, form, keyChoice, position in
        let level = keyLevels[levelIndex]
        let known = level.known[keyChoice % level.known.count]
        let text = exoticForms[form % exoticForms.count](known)
        return ConfigFlaw.exoticKey(level: level.path, key: text, position: position)
    }

    /// One top-level key's value anchored and another's an alias of it.
    static let aliased = zip(Pick.element(of: topKeys), Gen<Int>.value(in: 1...(topKeys.count - 1)))
        .map { anchored, offset in
            let alias = topKeys[((topKeys.firstIndex(of: anchored) ?? 0) + offset) % topKeys.count]
            return ConfigFlaw.aliased(anchored: anchored, alias: alias)
        }

    /// A flaw: an odd spelling mostly, else any other kind.
    static let flaw = Gen.frequency(
        (commonWeight, spelling),
        (classWeight, wrongType),
        (classWeight, badArguments),
        (classWeight, keyFault.map(ConfigFlaw.keyFault)),
        (classWeight, exoticKey),
        (rareWeight, aliased)
    )

    /// Text that isn't a configuration.
    static let soup = Gen.frequency((commonWeight, Pick.element(of: soupTokens)), (classWeight, UnicodeGen.fragment))
        .array(of: soupLength)
        .map { $0.joined() }

    /// The document start an empty configuration comes after.
    static let documentStart = "---\n"

    /// Any configuration text: valid, empty, flawed (most), or not a
    /// configuration.
    static let anyCase = zip(
        valid,
        layout,
        flaw,
        soup,
        Gen.frequency(
            (classWeight, Gen.always(Branch.valid)),
            (commonWeight, Gen.always(Branch.flawed)),
            (classWeight, Gen.always(Branch.soup)),
            (rareWeight, Gen.always(Branch.empty))
        )
    )
    .map { members, layout, flaw, soup, branch in
        guard branch != .empty else {
            let prefix = layout.prefix.hasSuffix(documentStart) ? layout.prefix : documentStart
            let blockLayout = ConfigLayout(flowDepth: blockDepth, prefix: prefix, endsInCRLF: layout.endsInCRLF)
            return ConfigCase(members: [], flaw: nil, soup: nil, layout: blockLayout)
        }
        return ConfigCase(
            members: members,
            flaw: branch == .flawed ? flaw : nil,
            soup: branch == .soup ? soup : nil,
            layout: layout
        )
    }
}
