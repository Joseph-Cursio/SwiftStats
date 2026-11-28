//
//  CollectorDecision.swift
//  SwiftStatsCoreTests
//
//  The decisions behind one `collectors.<name>` entry of a valid
//  configuration (PRD §10.1), and the entry they make for a name: no
//  value, an empty mapping, or a mapping of the parts drawn that the
//  collector takes. `path` is left out for the collectors that take none
//  (the build, the index and swifteffectinference), `arguments` for all
//  but coverage and swiftmutator, which take `--skip <regex>` pairs, or no
//  value (their reader's doc: "an absent or null value is no arguments");
//  and `options` holds `workers` and `timeout` under swiftmutator, or no
//  value ("an absent or null options gives neither"), anything under any
//  other collector.
//

/// The decisions behind one collector's entry.
struct CollectorDecision: Hashable, Sendable {
    /// The bit of the null spellings that writes `arguments` with no value.
    static let nullArgumentsBit = 1
    /// The bit that writes swiftmutator's `options` with no value.
    static let nullOptionsBit = 2

    /// The entry's form, modulo `ConfigGen.listForms`: no value, an empty
    /// mapping, or a mapping. The form divided by `ConfigGen.listForms`
    /// picks the null spellings, by `nullArgumentsBit` and
    /// `nullOptionsBit`.
    let form: Int
    /// `enabled`, as written, or nil for none.
    let enabled: String?
    /// `path`, or nil for none.
    let path: String?
    /// Whether the entry has `arguments`.
    let hasArguments: Bool
    /// The `--skip` patterns `arguments` pairs.
    let skips: [String]
    /// Whether the entry has `options`, and which of
    /// `ConfigGen.otherOptions` a collector other than swiftmutator gets,
    /// modulo their count; nil for none.
    let options: Int?
    /// swiftmutator's `workers`, or nil for none.
    let workers: String?
    /// swiftmutator's `timeout`, or nil for none.
    let timeout: String?

    /// Whether an entry's `arguments` has no value.
    var hasNullArguments: Bool {
        (form / ConfigGen.listForms) & Self.nullArgumentsBit != 0
    }

    /// Whether swiftmutator's `options` has no value.
    var hasNullOptions: Bool {
        (form / ConfigGen.listForms) & Self.nullOptionsBit != 0
    }

    /// The entry these decisions make for the collector `name`.
    func entry(for name: String) -> YAMLDraft? {
        switch form % ConfigGen.listForms {
        case 0:
            return nil

        case 1:
            return .mapping([])

        default:
            var members: [YAMLDraft.Member] = []
            if let enabled {
                members.append(YAMLDraft.member("enabled", .text(enabled)))
            }
            if let path, ConfigGen.pathless.contains(name) == false {
                members.append(YAMLDraft.member("path", .text(path)))
            }
            if hasArguments, ConfigGen.argumentTaking.contains(name) {
                let tokens = skips.flatMap { ["--skip", $0] }
                let arguments = YAMLDraft.sequence(tokens.map(YAMLDraft.text))
                members.append(YAMLDraft.member("arguments", hasNullArguments ? nil : arguments))
            }
            if let options {
                members.append(YAMLDraft.member("options", optionsValue(for: name, choice: options)))
            }
            return .mapping(members)
        }
    }

    /// These decisions as a mapping with `arguments` and `options`, their
    /// null spellings kept, and `workers` when given.
    func focused(workers focusedWorkers: String?) -> Self {
        Self(
            form: (form / ConfigGen.listForms + 1) * ConfigGen.listForms - 1,
            enabled: enabled,
            path: path,
            hasArguments: true,
            skips: skips,
            options: options ?? 0,
            workers: focusedWorkers ?? workers,
            timeout: timeout
        )
    }

    /// The `options` value for the collector `name`: swiftmutator's
    /// `workers` and `timeout` drawn, or no value, or another collector's
    /// choice.
    private func optionsValue(for name: String, choice: Int) -> YAMLDraft? {
        guard name == ConfigGen.mutator else {
            return ConfigGen.otherOptions[choice % ConfigGen.otherOptions.count]
        }
        guard hasNullOptions == false else {
            return nil
        }
        let members = [("workers", workers), ("timeout", timeout)].compactMap { key, value in
            value.map { YAMLDraft.member(key, .text($0)) }
        }
        return .mapping(members)
    }
}
